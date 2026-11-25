import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// DS-S6: a source whose `parse` keeps failing is mended in the background, from the responses it failed on;
/// until then its panel rows keep their last values, and once mended its home's conversation hears of it.
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

  static func agent(mending: FakeAgent.Behavior) -> FakeAgent {
    FakeAgent(provider: .codex) { prompt in prompt.hasPrefix(mend) ? mending : .reply("好的。") }
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

  @Test func aRepairRunMaySaveOnlyItsSourceAndRunsNoOtherCommand() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    try await withHost(agent: Self.agent(mending: .hang), sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(SourceLineTests.source()))
      runner.fail(Self.broken)
      await Self.fetch(3, on: host, world)

      world.tick()
      let run = try await Background.runSession(world)
      let session = LocalSession.run(run)

      let prompt = try #require(Background.prompts(world, starting: Self.mend).first)
      #expect(prompt.contains("fields[3] is undefined (line 4)"))
      #expect(prompt.contains("<external-content") && prompt.contains("v~changed"))
      #expect(prompt.contains("source test prem --script"))
      let panel = await Background.call(SavePanel(DataSourceScenarioTests.panel), from: session, on: host)
      #expect(panel == .failed(.invalidRequest(RunPolicy.repair.refusal(SavePanel.name))))
      let other = DataSource(name: "other", title: "x", every: SourceEvery(minutes: 1)!, script: "x")
      let elsewhere = await Background.call(SaveDataSource(other), from: session, on: host)
      #expect(elsewhere == .failed(.invalidRequest("This repair mends only the source prem; save that one.")))
      guard case .value? = await Background.call(TestDataSource("prem", script: "new"), from: session, on: host) else {
        Issue.record("the repair could not test its source")
        return
      }
      runner.fail(nil)
      let saved = await Background.call(SaveDataSource(SourceLineTests.source()), from: session, on: host)
      guard case .value? = saved else {
        Issue.record("the repair could not save its source: \(String(describing: saved))")
        return
      }
      #expect(try host.database.sourceSnapshot(SourceKey(.chat, "prem"))?.isBroken == false)
    }
  }

  @Test func aRepairedSourceIsToldInItsHomesConversation() async throws {
    let runner = FakeSources(records: SourceLineTests.records)
    try await withHost(agent: Self.agent(mending: .reply(Self.mended)), sources: runner) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let session = LocalSession.conversation(.project(project))
      _ = await Background.call(SaveDataSource(SourceLineTests.source()), from: session, on: host)
      runner.fail(Self.broken)
      await Self.fetch(3, on: host, world)

      world.tick()
      #expect(try await Background.ran(1, starting: Self.mend, on: host, world))

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
