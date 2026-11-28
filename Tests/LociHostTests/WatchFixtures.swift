import Foundation
import LociMedia
import LociModel
import LociStore
import Synchronization
import Testing

@testable import LociHost

/// What watch triage was given, read back from its prompt.
struct TriageInput: Decodable, Sendable {
  let watch: String
  let source: String
  let entries: [SourceEntry]
  let previousRecords: [String: SourceRecord]?
  let records: [String: SourceRecord]
  let otherSources: [String: [String: SourceRecord]]
  let panels: [String]
  let recent: [WatchFinding]

  private struct Wrapped: Decodable {
    let value: TriageInput
  }

  static func read(_ prompt: String) -> TriageInput? {
    guard let start = prompt.range(of: #"{"source":"external""#, options: .backwards) else { return nil }
    return try? JSONDecoder().decode(Wrapped.self, from: Data(prompt[start.lowerBound...].utf8)).value
  }
}

/// One decision of triage, as the tool model writes it.
struct TriageDecision: Encodable, Sendable {
  var id: String?
  var action: String
  var panel: String?
  var summary: String?
  var key: String?
  var reason: String?
  var evidenceIDs: [String]?
  var deadline: String?

  static func discard(_ id: String) -> Self { Self(id: id, action: "discard") }

  static func panel(_ id: String, _ panel: String, _ summary: String) -> Self {
    Self(id: id, action: "panel", panel: panel, summary: summary)
  }

  static func escalate(_ id: String?, key: String, summary: String, deadline: String) -> Self {
    Self(
      id: id, action: "escalate", summary: summary, key: key, reason: "跟你的持仓有关",
      evidenceIDs: id.map { [$0] } ?? [], deadline: deadline)
  }

  static func reply(_ decisions: [Self]) -> String {
    let data = (try? JSONEncoder().encode(["decisions": decisions])) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }
}

/// A tool model that answers watch triage as `decide` says, and keeps what each call was given; a call waits
/// while `held` is closed. Listing its models gives `fixture`.
actor TriageModel: Network {
  private let decide: @Sendable (TriageInput) -> String
  private(set) var inputs: [TriageInput] = []
  let held = Latch(open: true)
  /// What the service answers every call with while it is down, as an HTTP error.
  private var down: String?

  func go(down reason: String?) { down = reason }

  init(_ decide: @escaping @Sendable (TriageInput) -> String) {
    self.decide = decide
  }

  /// Discards every entry and says nothing of the numbers.
  static func discarding() -> TriageModel {
    TriageModel { input in TriageDecision.reply(input.entries.map { .discard($0.id) }) }
  }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    else { throw FetchError(reason: "no url") }
    if request.httpMethod == "GET" { return (Data(#"{"data":[{"id":"fixture"}]}"#.utf8), response) }
    guard let body = request.httpBody,
      let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let prompt = (payload["messages"] as? [[String: String]])?.first?["content"],
      let input = TriageInput.read(prompt)
    else { throw FetchError(reason: "not a triage request") }
    inputs.append(input)
    if let down { throw FetchError(reason: down) }
    await held.wait()
    let reply = decide(input)
    guard let data = try? JSONEncoder().encode(["choices": [["message": ["content": reply]]]]) else {
      throw FetchError(reason: "could not encode")
    }
    return (data, response)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "no downloads")
  }
}

/// The companion in the background, for a watch finding's or a follow-up's run: it does what `act` says from the
/// run's own session, then ends with `reply`; the conversations get `main`.
final class WatchCompanion: Sendable {
  static let prefix = "Something new may matter to the person"

  private let host = Mutex<LocalHost?>(nil)
  private let world = Mutex<TestWorld?>(nil)
  private let act: @Sendable (_ prompt: String, _ run: LocalSession, LocalHost) async -> Void
  private let reply: String
  private let main: FakeAgent.Behavior

  init(
    reply: String = WatchCompanion.silent, main: FakeAgent.Behavior = .reply("好的。"),
    act: @escaping @Sendable (_ prompt: String, _ run: LocalSession, LocalHost) async -> Void = { _, _, _ in }
  ) {
    self.reply = reply
    self.main = main
    self.act = act
  }

  static let silent = "SILENT"

  /// Puts up the card a finding's run would, with what it was told of the finding.
  static func carding(_ what: @escaping @Sendable (String) -> String = { _ in "国常会稳市" }) -> WatchCompanion {
    WatchCompanion { prompt, run, host in
      _ = await Background.call(AddNextUp(what(prompt), asking: "要调整吗？"), from: run, on: host)
    }
  }

  var agent: FakeAgent {
    FakeAgent(provider: .codex) { [self] prompt in
      guard prompt.hasPrefix(Self.prefix) || prompt.hasPrefix(Background.followUp) else { return main }
      return .replyWhenLetGo(reply) { [self] in
        guard let host = host.withLock({ $0 }), let world = world.withLock({ $0 }),
          let session = world.agent.opened.compactMap({ $0.environment[LocalCall.sessionVariable] })
            .compactMap(LocalSession.init(tag:)).last
        else { return }
        await act(prompt, session, host)
      }
    }
  }

  func attach(_ host: LocalHost, _ world: TestWorld) {
    self.host.withLock { $0 = host }
    self.world.withLock { $0 = world }
  }
}

/// A host with sources fetched by `sources`, the tool model `model` set up, and `companion` for runs.
func withWatchHost(
  model: TriageModel, sources: FakeSources = FakeSources(), companion: WatchCompanion = WatchCompanion(),
  _ body: (LocalHost, Place, TestWorld) async throws -> Void
) async throws {
  try await withHost(agent: companion.agent, sources: sources, models: model) { host, place, world in
    companion.attach(host, world)
    _ = try await configureModels(host)
    try await body(host, place, world)
  }
}

enum Watching {
  /// The source of quick news the samples use, fetched every two minutes.
  static let news = DataSource(
    name: "news", title: "财联社电报", every: SourceEvery(minutes: 2)!, script: "function requests() {}")

  /// The fetches that are due, then triage of what they brought; a run it raised has started when it returns.
  static func fetch(on host: LocalHost) async {
    _ = await SourceLineTests.look(host)
    await host.watchTriage.settled()
  }

  /// Moves the clock on to the next fetch and does it.
  static func fetchNext(on host: LocalHost, _ world: TestWorld, minutes: Int64 = 2) async {
    world.advance(minutes: minutes)
    await fetch(on: host)
  }

  static func findings(_ host: LocalHost) throws -> [WatchFinding] {
    try host.database.openEvents().compactMap { if case .watch(let finding, _) = $0.source { finding } else { nil } }
  }

  /// Every watch finding the inbox holds, open or done.
  static func raised(in home: Home = .chat, _ host: LocalHost) throws -> [WatchFinding] {
    try host.database.recentWatchFindings(in: home, limit: 100)
  }
}

extension Watching {
  /// A finding raised as triage raises one, with its own key.
  @discardableResult
  static func raise(
    _ summary: String, deadline: Timestamp, in home: Home = .chat, on host: LocalHost, _ world: TestWorld
  ) throws -> Event {
    let finding = WatchFinding(
      key: summary, summary: summary, reason: "跟你有关",
      evidence: [WatchFinding.Evidence(title: summary, source: news.title, at: world.now)])
    let event = Event(
      id: world.nextID(), source: .watch(finding, project: home.project), due: world.now, deadline: deadline,
      depth: 1)
    try host.database.raise(event)
    return event
  }

  static func minutes(_ minutes: Int64, after moment: Timestamp) -> Timestamp {
    Timestamp(millisecondsSince1970: moment.millisecondsSince1970 + minutes * 60_000)
  }
}
