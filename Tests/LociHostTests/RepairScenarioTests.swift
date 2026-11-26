import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// DS-S6: a source whose `parse` keeps failing is mended in the background, from the responses it failed on;
/// until then its panel rows keep their last values, and once mended its home's conversation hears of it. The
/// repair may save only the source it was granted, only while it runs, only a script that reads what broke
/// it, and only over the definition it was given; whether it mended the source is the app's to say.
@Suite(.timeLimit(.minutes(1)))
struct RepairScenarioTests {
  static let mend = "Mend the data source"
  static let mended = "腾讯把价格挪到了第 4 段，parse 改从那里读。"
  static let problems = SourceProblems("parse", "fields[3] is undefined (line 4)")
  static let broken = SourceFailure.script(
    problems,
    sample: SourceSample(
      at: TestWorld.instant, state: nil, requests: [],
      responses: [SourceResponse(url: URL(string: "https://qt.gtimg.cn/q=sh513870")!, status: 200, text: "v~changed")]))
  static let fixed = DataSource(
    name: "prem", title: "ETF 溢价", every: SourceEvery(minutes: 1)!, script: "function requests() {} // fixed")

  static func agent(mending: FakeAgent.Behavior) -> FakeAgent {
    FakeAgent(provider: .codex) { prompt in prompt.hasPrefix(mend) ? mending : .reply("好的。") }
  }

  /// A repair that replies once the test lets it go, having done meanwhile what the test did in its session.
  static func held() -> (FakeAgent, AsyncStream<Void>.Continuation) {
    let (gate, open) = AsyncStream.makeStream(of: Void.self)
    return (agent(mending: .replyWhenLetGo(mended, after: { for await _ in gate { return } })), open)
  }

  /// Fetches the source `times` times, a minute apart.
  static func fetch(_ times: Int, on host: LocalHost, _ world: TestWorld) async {
    for _ in 0..<times {
      world.advance(minutes: 1)
      _ = await SourceLineTests.look(host)
    }
  }

  static func repairs(_ host: LocalHost) throws -> [Event] {
    try host.database.openEvents().filter { $0.source.repair != nil }
  }

  /// Saves the source, breaks it, and starts its repair; the repair's session.
  static func broken(_ host: LocalHost, _ world: TestWorld, _ runner: FakeSources) async throws -> LocalSession {
    _ = try await host.run(SaveDataSource(SourceLineTests.source()))
    runner.fail(Self.broken)
    await fetch(3, on: host, world)
    world.tick()
    let session = LocalSession.run(try await Background.runSession(world))
    _ = try #require(await prompt(world))
    return session
  }

  static func prompt(_ world: TestWorld) async -> String? {
    for _ in 0..<500 {
      if let prompt = Background.prompts(world, starting: mend).first { return prompt }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
  }

  static func isBroken(_ host: LocalHost) throws -> Bool {
    try host.database.sourceSnapshot(SourceKey(.chat, "prem"))?.isBroken == true
  }

  static func refusal(_ reply: LocalReply?) -> String? {
    if case .failed(.invalidRequest(let why))? = reply { why } else { nil }
  }

  @Test func threeParseFailuresInARowRaiseOneRepair() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    try await withHost(sources: runner) { host, place, world in
      _ = try await host.run(SaveDataSource(SourceLineTests.source()))
      runner.fail(Self.broken)
      await Self.fetch(1, on: host, world)
      let since = world.now
      await Self.fetch(1, on: host, world)
      runner.fail(.unreachable(SourceProblems("requests[0]", "HTTP 502")))
      await Self.fetch(1, on: host, world)
      #expect(try Self.repairs(host).isEmpty)

      runner.fail(Self.broken)
      await Self.fetch(1, on: host, world)
      await Self.fetch(2, on: host, world)

      let repairs = try Self.repairs(host)
      #expect(repairs.map(\.source) == [.source("prem", project: nil)])
      #expect(repairs.first?.key == "source/home/prem/broken/\(since)")
      let snapshot = try #require(try host.database.sourceSnapshot(SourceKey(.chat, "prem")))
      #expect(snapshot.isBroken && snapshot.records == SourceLineTests.records)
      #expect(place.store.samples(of: "prem", in: DataSourceFolder(.chat)).count == 4)
    }
  }

  @Test func aRepairMaySaveOnlyItsSourceAndRunsNoOtherCommand() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    try await withHost(agent: Self.agent(mending: .hang), sources: runner) { host, _, world in
      let session = try await Self.broken(host, world, runner)

      for _ in 0..<500 where Background.prompts(world, starting: Self.mend).isEmpty {
        try await Task.sleep(for: .milliseconds(10))
      }
      let prompt = try #require(Background.prompts(world, starting: Self.mend).first)
      #expect(prompt.contains("fields[3] is undefined (line 4)"))
      #expect(prompt.contains("<external-content") && prompt.contains("v~changed"))
      #expect(prompt.contains("source test prem --script"))
      let panel = await Background.call(SavePanel(DataSourceScenarioTests.panel), from: session, on: host)
      #expect(Self.refusal(panel) == RunPolicy.repair.refusal(SavePanel.name))
      let other = DataSource(name: "other", title: "x", every: SourceEvery(minutes: 1)!, script: "x")
      let elsewhere = await Background.call(SaveDataSource(other), from: session, on: host)
      #expect(Self.refusal(elsewhere) == "This repair mends only the source prem; use that one.")
      guard case .value? = await Background.call(TestDataSource("prem", script: "new"), from: session, on: host) else {
        Issue.record("the repair could not test its source")
        return
      }
      runner.fail(nil)
      let saved = await Background.call(SaveDataSource(Self.fixed), from: session, on: host)
      guard case .value? = saved else {
        Issue.record("the repair could not save its source: \(String(describing: saved))")
        return
      }
      #expect(try !Self.isBroken(host))
      #expect(runner.replayed.contains(Self.fixed.script))
    }
  }

  @Test func aScriptThatStillFailsTheSamplesThatBrokeTheSourceIsNotSaved() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    try await withHost(agent: Self.agent(mending: .hang), sources: runner) { host, place, world in
      let session = try await Self.broken(host, world, runner)
      runner.fail(nil)
      runner.failReplays(SourceProblems("parse", "still no price"))

      let reply = await Background.call(SaveDataSource(Self.fixed), from: session, on: host)

      guard case .value(let data)? = reply else {
        Issue.record("refused otherwise: \(String(describing: reply))")
        return
      }
      guard case .failed(let problems) = try JSONDecoder().decode(SourceOutcome.self, from: data) else {
        Issue.record("saved")
        return
      }
      #expect(problems.all.allSatisfy { $0.description.contains("still no price") })
      #expect(try Self.isBroken(host))
      #expect(place.store.dataSource(named: "prem", in: DataSourceFolder(.chat)) == SourceLineTests.source())
    }
  }

  @Test func aRepairThatOnlySaysItMendedTheSourceHasNotMendedIt() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    try await withHost(agent: Self.agent(mending: .reply(Self.mended)), sources: runner) { host, _, world in
      _ = try await Self.broken(host, world, runner)

      #expect(try await Background.ran(1, starting: Self.mend, on: host, world))

      #expect(try Self.isBroken(host))
      let run = try #require(try host.database.runs(startedAfter: TestWorld.instant).first)
      #expect(run.outcome == .failed(Worker.notMended, tries: 1))
      #expect(try await host.conversation(.main).messages.allSatisfy { $0.body != .told(Self.mended) })
    }
  }

  @Test func aSaveOnceTheRepairIsOverOrOverAChangedSourceIsRefused() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    let (agent, letGo) = Self.held()
    try await withHost(agent: agent, sources: runner) { host, place, world in
      let session = try await Self.broken(host, world, runner)
      runner.fail(nil)
      let changed = DataSource(name: "prem", title: "ETF 溢价", every: SourceEvery(minutes: 5)!, script: "by you")
      _ = try await host.run(SaveDataSource(changed))

      let over = await Background.call(SaveDataSource(Self.fixed), from: session, on: host)
      letGo.yield()
      #expect(try await Background.ran(1, starting: Self.mend, on: host, world))
      let after = await Background.call(SaveDataSource(Self.fixed), from: session, on: host)

      #expect(Self.refusal(over) == "The source changed or works again since this repair began; nothing was saved.")
      #expect(Self.refusal(after) == ToolGateway.over)
      #expect(place.store.dataSource(named: "prem", in: DataSourceFolder(.chat)) == changed)
    }
  }

  @Test func aSaveStillReplayingWhenTheRepairEndsKeepsNothing() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    let (agent, letGo) = Self.held()
    try await withHost(agent: agent, sources: runner) { host, place, world in
      let session = try await Self.broken(host, world, runner)
      runner.fail(nil)
      runner.holdReplays()
      let saving = Task { await Background.call(SaveDataSource(Self.fixed), from: session, on: host) }
      for _ in 0..<500 where runner.replaying == 0 { try await Task.sleep(for: .milliseconds(10)) }
      #expect(runner.replaying > 0)

      letGo.yield()
      #expect(try await Background.ran(1, starting: Self.mend, on: host, world))
      runner.release()
      let saved = await saving.value

      #expect(Self.refusal(saved) == RepairGrant.over)
      #expect(place.store.dataSource(named: "prem", in: DataSourceFolder(.chat)) == SourceLineTests.source())
      #expect(try Self.isBroken(host))
      let run = try #require(try host.database.runs(startedAfter: TestWorld.instant).first)
      #expect(run.outcome == .failed(Worker.notMended, tries: 1))
    }
  }

  @Test func aSourceThatWorksAgainWithoutTheRepairsSaveIsNotToldAsMended() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    let (agent, letGo) = Self.held()
    try await withHost(agent: agent, sources: runner) { host, _, world in
      _ = try await Self.broken(host, world, runner)
      runner.fail(nil)
      await Self.fetch(1, on: host, world)
      #expect(try !Self.isBroken(host))

      letGo.yield()
      #expect(try await Background.ran(1, starting: Self.mend, on: host, world))

      let run = try #require(try host.database.runs(startedAfter: TestWorld.instant).first)
      #expect(run.outcome == .failed(Worker.notMended, tries: 1))
      #expect(try await host.conversation(.main).messages.allSatisfy { $0.body != .told(Self.mended) })
    }
  }

  @Test func aRepairListsOnlyTheSourceItMends() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    try await withHost(agent: Self.agent(mending: .hang), sources: runner) { host, _, world in
      let other = DataSource(name: "other", title: "别的", every: SourceEvery(minutes: 60)!, script: "x")
      _ = try await host.run(SaveDataSource(other))
      let session = try await Self.broken(host, world, runner)

      let listed = await Background.call(ListDataSources(), from: session, on: host)

      guard case .value(let data)? = listed else {
        Issue.record("the repair could not list its source: \(String(describing: listed))")
        return
      }
      #expect(try JSONDecoder().decode([DataSourceEntry].self, from: data).map(\.source.name) == ["prem"])
    }
  }

  @Test func aRepairedSourceIsToldInItsHomesConversation() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    let (agent, letGo) = Self.held()
    try await withHost(agent: agent, sources: runner) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let conversation = LocalSession.conversation(.project(project))
      _ = await Background.call(SaveDataSource(SourceLineTests.source()), from: conversation, on: host)
      runner.fail(Self.broken)
      await Self.fetch(3, on: host, world)
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))
      _ = try #require(await Self.prompt(world))
      runner.fail(nil)
      _ = await Background.call(SaveDataSource(Self.fixed), from: session, on: host)
      letGo.yield()
      #expect(try await Background.ran(1, starting: Self.mend, on: host, world))

      let told = await value(host.subscribe(OneConversation(.project(project)))) { conversation in
        conversation.messages.contains { $0.body == .told(Self.mended) }
      }
      #expect(told != nil)
      #expect(try await host.conversation(.main).messages.allSatisfy { $0.body != .told(Self.mended) })

      _ = try await host.run(SendMessage(to: .main, text: "后台做了什么"))
      _ = try #require(await settled(host))
      #expect(world.agent.prompts.last?.contains(Self.mended) == false)
      _ = try await host.run(SendMessage(to: .project(project), text: "后台做了什么"))
      _ = try #require(await settled(host, .project(project), prompts: 2))
      #expect(world.agent.prompts.last?.contains("source prem: \(Self.mended)") == true)
    }
  }

  @Test func aRepairForASourceThatWorksAgainIsDropped() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    try await withHost(agent: Self.agent(mending: .hang), sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(SourceLineTests.source()))
      runner.fail(Self.broken)
      await Self.fetch(3, on: host, world)
      runner.fail(nil)
      await Self.fetch(1, on: host, world)

      world.tick()
      try await Background.quiet()

      #expect(try Self.repairs(host).isEmpty)
      #expect(Background.prompts(world, starting: Self.mend).isEmpty)
    }
  }
}
