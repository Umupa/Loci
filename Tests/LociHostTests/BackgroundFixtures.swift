import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// What the tests of runs in the background share. The companion runs on Codex in all of them.
enum Background {
  static let lookInto = "Look into something on your own"
  static let followUp = "Do what you told yourself you would"
  static let together = "Several things came due together"

  /// Answers runs as `run` says and the conversations with a hello.
  static func agent(
    main: FakeAgent.Behavior = .reply("Hello there."), run: @escaping @Sendable (String) -> FakeAgent.Behavior
  ) -> FakeAgent {
    FakeAgent(provider: .codex) { prompt in
      prompt.hasPrefix(lookInto) || prompt.hasPrefix(followUp) || prompt.hasPrefix(together) ? run(prompt) : main
    }
  }

  static func clock(_ time: String) throws -> TimeOfDay { try #require(TimeOfDay(time)) }

  static func draft(
    _ every: Every, to destination: Destination = .notes, follow: String = "看看 CubeSandbox 有什么新动静"
  ) -> ScheduleDraft {
    ScheduleDraft(title: "CubeSandbox 动静", follow: follow, every: every, destination: destination)
  }

  /// Adds a schedule the way the companion does, with `loci schedule add` in the main conversation.
  static func add(_ name: String, _ draft: ScheduleDraft, on host: LocalHost) async throws -> ScheduleEntry {
    let reply = await call(AddSchedule(name, draft), from: .conversation(.main), on: host)
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode(ScheduleEntry.self, from: data)
  }

  /// What the app answers a `loci` command with, from a session.
  static func call<C: Command>(_ command: C, from session: LocalSession?, on host: LocalHost) async -> LocalReply? {
    guard let body = try? JSONEncoder().encode(command) else { return nil }
    return await call(.command(name: C.name, body: body), from: session, on: host)
  }

  static func call(_ request: LocalCall.Request, from session: LocalSession?, on host: LocalHost) async
    -> LocalReply?
  {
    let replies = Replies()
    await ToolGateway.answer(LocalCall(session: session, request: request), on: host) { await replies.add($0) }
    return await replies.all.first
  }

  private actor Replies {
    var all: [LocalReply] = []
    func add(_ reply: LocalReply) { all.append(reply) }
  }

  /// The schedule's runs once `match` holds for them.
  static func runs(
    of schedule: ScheduleRef, on host: LocalHost, where match: @escaping @Sendable ([Run]) -> Bool
  ) async -> [Run]? {
    await value(host.subscribe(WatchScheduleRuns(schedule)), where: match)
  }

  static func finished(_ runs: [Run]) -> Bool {
    runs.first.map { if case .running = $0.outcome { false } else { true } } ?? false
  }

  /// The session the first run in the background was opened with, once it was.
  static func runSession(_ world: TestWorld) async throws -> Run.ID {
    for _ in 0..<500 {
      let tags = world.agent.opened.compactMap { $0.environment[LocalCall.sessionVariable] }
      for case .run(let run)? in tags.map(LocalSession.init(tag:)) { return run }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw HostError.notFound("run session")
  }

  static func prompts(_ world: TestWorld, starting prefix: String) -> [String] {
    world.agent.prompts.filter { $0.hasPrefix(prefix) }
  }

  /// Waits until `count` runs were asked with `prefix`, and the last of them is over.
  static func ran(_ count: Int, starting prefix: String, on host: LocalHost, _ world: TestWorld) async throws -> Bool {
    for _ in 0..<1000 where prompts(world, starting: prefix).count < count {
      try await Task.sleep(for: .milliseconds(10))
    }
    guard prompts(world, starting: prefix).count >= count else { return false }
    return await value(host.subscribe(LociWorking())) { $0.work == nil } != nil
  }

  /// Long enough for a run that would start to have started.
  static func quiet() async throws {
    try await Task.sleep(for: .milliseconds(150))
  }
}
