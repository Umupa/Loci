import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// PJ-S6, PJ-S9–PJ-S11: archiving, deleting or keeping a project out of memory stops what is under way there,
/// what returns late writes nothing, what waited runs once the project is back, and a deletion for good leaves
/// nothing of it in the database.
@Suite(.timeLimit(.minutes(1)))
struct ProjectLifecycleTests {
  static func idle(_ host: LocalHost) async {
    _ = await value(host.subscribe(LociWorking())) { $0.work == nil }
  }

  static func events(of project: Project.ID, on host: LocalHost) throws -> [Event] {
    try host.database.openEvents().filter { $0.source.home == .project(project) }
  }

  @Test func aFollowUpQueuedBeforeTheProjectIsArchivedRunsOnceItIsBack() async throws {
    let agent = FakeAgent(provider: .codex) { prompt in
      if prompt.hasSuffix("等一下") { return .hang }
      return prompt.hasPrefix(Background.followUp) ? .reply("看过了。") : .reply("好")
    }
    try await withHost(agent: agent) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      _ = await Background.call(
        AddFollowUp(.after(minutes: 60), "看看那只基金"), from: .conversation(.project(project)), on: host)
      _ = try await host.run(SendMessage(to: .main, text: "等一下"))
      world.advance(minutes: 60)
      world.tick()
      while try Self.events(of: project, on: host).isEmpty { try await Task.sleep(for: .milliseconds(10)) }

      _ = try await host.run(ArchiveProject(project, archived: true))
      _ = try await host.run(StopTurn(in: .main))
      try await Background.quiet()
      #expect(Background.prompts(world, starting: Background.followUp).isEmpty)
      #expect(try Self.events(of: project, on: host).count == 1)

      _ = try await host.run(ArchiveProject(project, archived: false))
      for _ in 0..<300 where Background.prompts(world, starting: Background.followUp).isEmpty {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(Background.prompts(world, starting: Background.followUp).count == 1)
    }
  }

  @Test func archivingStopsTheProjectsRunAndItsEventWaitsForTheProjectToComeBack() async throws {
    try await withHost(agent: Background.agent { _ in .hang }) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let entry = try await ProjectBackgroundTests.addSchedule(in: project, on: host)
      world.advance(minutes: 60)
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))

      _ = try await host.run(ArchiveProject(project, archived: true))
      let late = await Background.call(AddFollowUp(.after(minutes: 5), "再看"), from: session, on: host)
      await Self.idle(host)

      #expect(RunToolScenarioTests.refused(late) == ToolGateway.stopped)
      #expect(try host.database.followUps().filter { $0.home == .project(project) }.isEmpty)
      let waiting = try Self.events(of: project, on: host)
      #expect(waiting.map(\.state) == [.waiting(nil)])
      let stopped = try host.database.runs(of: entry.ref, limit: 5).first?.outcome
      #expect(stopped == .failed("stopped: its project was closed", tries: 1))

      let opened = world.agent.opened.count
      _ = try await host.run(ArchiveProject(project, archived: false))
      for _ in 0..<300 where world.agent.opened.count == opened { try await Task.sleep(for: .milliseconds(10)) }
      #expect(world.agent.opened.count > opened)
    }
  }

  @Test func aFetchThatReturnsAfterTheProjectIsDeletedWritesNothing() async throws {
    let runner = FakeSources(records: ["513870": ["premium": .number(0.159)]])
    try await withHost(agent: FakeAgent(provider: .codex), sources: runner) { host, place, world in
      let project = try await ProjectScenarioTests.start(host)
      _ = await Background.call(
        SaveDataSource(DataSourceScenarioTests.source), from: .conversation(.project(project)), on: host)
      runner.hold()
      world.advance(minutes: 1)
      let fetches = await host.sourceLine.look()

      _ = try await host.run(DeleteProject(project))
      runner.set(["513870": ["premium": .number(0.2)]])
      runner.release()
      for fetch in fetches { await fetch.value }

      #expect(!FileManager.default.fileExists(atPath: place.store.home(.project(project)).folder.path()))
      _ = try await host.run(RestoreDeletedProject())
      let snapshot = try host.database.sourceSnapshot(SourceKey(.project(project), "prem"))
      #expect(snapshot?.records["513870"]?["premium"] == .number(0.159))
    }
  }

  @Test func aProjectDeletedForGoodLeavesNothingInTheDatabase() async throws {
    let agent = Background.agent { _ in .reply("纳指回撤到二十日线。") }
    try await withHost(agent: agent) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let session = LocalSession.conversation(.project(project))
      let entry = try await ProjectBackgroundTests.addSchedule(in: project, on: host)
      _ = await Background.call(AddFollowUp(.after(minutes: 600), "看看赎回费"), from: session, on: host)
      _ = await Background.call(AddNextUp("纳指回撤", asking: "还定投吗"), from: session, on: host)
      world.advance(minutes: 60)
      world.tick()
      let run = try #require(await Background.runs(of: entry.ref, on: host, where: Background.finished)?.first)
      let other = try await ProjectScenarioTests.start(host, named: "旅行")

      _ = try await host.run(DeleteProject(project))
      _ = try await host.run(DeleteProject(other))

      let database = host.database
      #expect(try database.run(run.id) == nil)
      #expect(try database.runs(of: entry.ref, limit: 5).isEmpty)
      guard case .schedule(let schedule) = entry.ref else { throw HostError.invalidRequest("not a schedule") }
      #expect(try database.schedule(schedule) == nil)
      #expect(try database.followUps().filter { $0.home == .project(project) }.isEmpty)
      #expect(try database.openEvents().filter { $0.source.home == .project(project) }.isEmpty)
      #expect(try database.nextUps(of: [.project(project)]).isEmpty)
      #expect(try database.recall("纳指回撤到二十日线").isEmpty)
      #expect(try database.latestReply(in: .project(project)) == nil)
    }
  }

  @Test func keepingAProjectOutOfMemoryStopsItsReviewWhichWaitsUntilItIsRememberedAgain() async throws {
    let reviewing: @Sendable (String) -> Bool = { $0.hasPrefix("It is the end of") && $0.contains("in the project") }
    let agent = FakeAgent(provider: .codex) { prompt in reviewing(prompt) ? .hang : .reply("好") }
    try await withHost(agent: agent) { host, place, world in
      world.set(to: "22:00")
      let project = try await ProjectScenarioTests.start(host)
      world.set(to: "23:30")
      world.tick()
      for _ in 0..<500 where !world.agent.prompts.contains(where: reviewing) {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(place.store.home(.project(project)).memoryIsWritable)

      _ = try await host.run(SetProjectRemembered(project, remembered: false))
      await Self.idle(host)

      #expect(!place.store.home(.project(project)).memoryIsWritable)
      #expect(try Self.events(of: project, on: host).map(\.state) == [.waiting(nil)])

      _ = try await host.run(SetProjectRemembered(project, remembered: true))
      for _ in 0..<500 where world.agent.prompts.filter(reviewing).count < 2 {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(world.agent.prompts.filter(reviewing).count == 2)
    }
  }

  @Test func keepingAProjectOutOfMemoryLeavesItsScheduleAndFetchesAtWork() async throws {
    let runner = FakeSources(records: ["513870": ["premium": .number(0.159)]])
    try await withHost(agent: Background.agent { _ in .hang }, sources: runner) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      _ = await Background.call(
        SaveDataSource(DataSourceScenarioTests.source), from: .conversation(.project(project)), on: host)
      _ = try await ProjectBackgroundTests.addSchedule(in: project, on: host)
      world.advance(minutes: 60)
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))
      _ = await host.sourceLine.look()
      runner.hold()
      world.advance(minutes: 1)
      let fetches = await host.sourceLine.look()
      #expect(!fetches.isEmpty)

      _ = try await host.run(SetProjectRemembered(project, remembered: false))
      runner.set(["513870": ["premium": .number(0.2)]])
      runner.release()
      for fetch in fetches { await fetch.value }
      let later = await Background.call(AddFollowUp(.after(minutes: 5), "再看"), from: session, on: host)

      #expect(RunToolScenarioTests.worked(later))
      let snapshot = try host.database.sourceSnapshot(SourceKey(.project(project), "prem"))
      #expect(snapshot?.records["513870"]?["premium"] == .number(0.2))
    }
  }

  @Test func aRunThatEndsAfterItsProjectIsDeletedForGoodWritesNothingBackNorMakesItsFolderAgain() async throws {
    try await withHost(agent: Background.agent { _ in .hang }) { host, place, world in
      let project = try await ProjectScenarioTests.start(host)
      let entry = try await ProjectBackgroundTests.addSchedule(in: project, on: host)
      world.advance(minutes: 60)
      world.tick()
      _ = try await Background.runSession(world)
      let other = try await ProjectScenarioTests.start(host, named: "旅行")

      _ = try await host.run(DeleteProject(project))
      _ = try await host.run(DeleteProject(other))
      await Self.idle(host)

      #expect(try host.database.runs(of: entry.ref, limit: 5).isEmpty)
      #expect(try Self.events(of: project, on: host).isEmpty)
      #expect(!FileManager.default.fileExists(atPath: place.store.home(.project(project)).folder.path()))
    }
  }

  @Test func aCallFromARunThatIsOverIsRefusedAndLandsNowhere() async throws {
    try await withHost(agent: Background.agent { _ in .reply("纳指回撤到二十日线。") }) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let entry = try await ProjectBackgroundTests.addSchedule(in: project, on: host)
      world.advance(minutes: 60)
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))
      _ = try #require(await Background.runs(of: entry.ref, on: host, where: Background.finished)?.first)

      let late = await Background.call(AddFollowUp(.after(minutes: 5), "再看"), from: session, on: host)
      let card = await Background.call(AddNextUp("纳指回撤", asking: "还定投吗"), from: session, on: host)

      #expect(RunToolScenarioTests.refused(late) == ToolGateway.over)
      #expect(RunToolScenarioTests.refused(card) == ToolGateway.over)
      #expect(try host.database.followUps().isEmpty)
      #expect(try await host.nextUps(of: .chat).isEmpty)
    }
  }
}
