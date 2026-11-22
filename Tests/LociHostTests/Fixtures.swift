import Foundation
import LociAgents
import LociModel
import LociStore
import Synchronization
import Testing

@testable import LociHost

/// Identifiers in a fixed sequence, a clock that moves only when told, and ticks that come only when sent.
final class TestWorld: Sendable {
  private let created: Mutex<UInt64>
  private let looks = Mutex<[Bool]>([])
  private let clock = Mutex<Timestamp>(TestWorld.instant)
  private let ticking = AsyncStream.makeStream(of: Void.self)
  /// What the Mac seems to have installed: Pi only.
  static let installed: [AgentInstallation] = Provider.allCases.map { provider in
    provider == .pi
      ? .installed(
        .init(
          provider: .pi, executable: HostPath(URL(filePath: "/usr/local/bin/pi")), version: "0.62.0", signIn: .unknown))
      : .missing(provider)
  }
  /// 2025-11-17 08:00:00.123 in Shanghai, a Monday morning.
  static let instant = Timestamp(millisecondsSince1970: 1_763_337_600_123)
  static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
  let agent: FakeAgent

  init(agent: FakeAgent = FakeAgent(), idOffset: UInt64 = 0) {
    created = Mutex(idOffset)
    self.agent = agent
  }

  var environment: HostEnvironment {
    environment(
      running: { [agent] provider in provider == agent.provider ? agent : nil },
      runtime: Runtime(provider: agent.provider))
  }

  func environment(
    running agents: @escaping @Sendable (Provider) async -> (any AgentDriver)?, tool: AgentTool? = nil,
    runtime: Runtime = Runtime(provider: .pi)
  ) -> HostEnvironment {
    HostEnvironment(
      newID: { [self] in self.nextID() }, now: { [self] in self.now }, timeZone: Self.timeZone,
      defaultRuntime: runtime, discard: .permanently, agents: agents,
      detectAgents: { [self] again in
        self.looks.withLock { $0.append(again) }
        return Self.installed
      }, ticks: { [ticking] in ticking.stream }, tool: tool)
  }

  var now: Timestamp { clock.withLock { $0 } }

  func advance(minutes: Int64) {
    clock.withLock { $0 = Timestamp(millisecondsSince1970: $0.millisecondsSince1970 + minutes * 60_000) }
  }

  /// Sets the clock to a time of day in Shanghai on the day it shows now, or on later days.
  func set(to time: String, daysLater: Int = 0) {
    let day = Day(containing: now, in: Self.timeZone).adding(days: daysLater)
    let clock = TimeOfDay(time) ?? TimeOfDay(of: now, in: Self.timeZone)
    let start = day.start(in: Self.timeZone).millisecondsSince1970
    self.clock.withLock {
      $0 = Timestamp(millisecondsSince1970: start + Int64(clock.hour * 60 + clock.minute) * 60_000)
    }
  }

  /// What the app's clock does once a minute.
  func tick() {
    ticking.continuation.yield()
  }

  /// Each time the host looked for agents, whether it was asked to look again.
  var lookedAgain: [Bool] { looks.withLock { $0 } }

  func nextID() -> EntityID {
    let seed = created.withLock { count in
      count += 1
      return count
    }
    var entropy = SeededGenerator(seed: seed)
    return EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + Double(seed)), entropy: &entropy)
  }
}

/// A temporary Loci folder and database location, deleted afterwards.
struct Place {
  let root: URL
  var database: URL { root.appending(path: "loci.sqlite") }
  var store: Store { Store(root: root, discard: .permanently) }

  init(root: URL = FileManager.default.temporaryDirectory.appending(path: "loci-host-\(UUID().uuidString)")) {
    self.root = root
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  /// Rewrites a file the way an agent or the Finder would, without going through the host.
  func edit(_ url: URL, _ change: (String) -> String) throws {
    try Data(change(try String(contentsOf: url, encoding: .utf8)).utf8).write(to: url)
  }
}

/// Runs `body` against a host started in a new temporary place, then closes it and deletes the place.
func withHost(
  agent: FakeAgent = FakeAgent(), _ body: (LocalHost, Place, TestWorld) async throws -> Void
) async throws {
  let place = Place()
  defer { place.remove() }
  let world = TestWorld(agent: agent)
  let host = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
  do {
    try await body(host, place, world)
  } catch {
    await host.close()
    throw error
  }
  await host.close()
}

/// How long a test waits for what the host will do before it gives up. Every host test runs at the same time,
/// and on a runner with three cores the whole run can take longer than a few seconds, so a wait that short
/// fails because the machine is busy rather than because the host is wrong. Nothing a host test waits for is on
/// a timer, since ticks come only when the test sends them; this only stops a test that would wait forever.
let patience: Duration = .seconds(60)

/// The first value the feed delivers that satisfies `match`, or `nil` after `timeout`.
func first<Value: Sendable>(
  _ feed: AsyncStream<Feed<Value>>, within timeout: Duration = patience,
  where match: @escaping @Sendable (Feed<Value>) -> Bool
) async -> Feed<Value>? {
  await withTaskGroup(of: Feed<Value>?.self) { group in
    group.addTask {
      for await delivered in feed where match(delivered) { return delivered }
      return nil
    }
    group.addTask {
      try? await Task.sleep(for: timeout)
      return nil
    }
    let found = await group.next() ?? nil
    group.cancelAll()
    return found
  }
}

func value<Value: Sendable>(
  _ feed: AsyncStream<Feed<Value>>, within timeout: Duration = patience,
  where match: @escaping @Sendable (Value) -> Bool
) async -> Value? {
  let found = await first(feed, within: timeout) { delivered in
    if case .value(let value) = delivered { return match(value) }
    return false
  }
  guard case .value(let value) = found else { return nil }
  return value
}

struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}

/// The conversation once no turn runs and the person has sent `prompts` messages.
func settled(_ host: LocalHost, _ conversation: ConversationRef = .main, prompts: Int = 1) async -> Conversation? {
  await value(host.subscribe(OneConversation(conversation))) { conversation in
    conversation.turn == nil && conversation.messages.count { $0.isTyped } == prompts
  }
}

extension Conversation {
  var messages: [Message] {
    entries.compactMap { entry in
      if case .message(let message) = entry { message } else { nil }
    }
  }

  var bodies: [Message.Body] { messages.map(\.body) }
}

extension String {
  /// What the person typed, after the context the app put in front of it.
  var typed: String {
    components(separatedBy: "</loci-context>\n\n").last ?? self
  }
}

enum Fixture {
  /// An article to read and mark.
  static let schedulingText = "# 调度\n\n调度器先排除不合适的节点，再给剩下的节点打分。\n"
}

/// Waits until a manual agent's session has started answering in the conversation.
func working(_ host: LocalHost, _ conversation: ConversationRef = .main) async -> Bool {
  await value(host.subscribe(OneConversation(conversation))) {
    $0.turn?.messages.contains { $0.body == .reply("Waiting") } == true
  } != nil
}
