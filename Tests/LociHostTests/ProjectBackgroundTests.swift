import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// PJ-S5, PJ-S6, PJ-S10: a project's schedules and reviews work in the project's folder with its memory, and
/// what they did is told in the project, never in the main conversation.
@Suite(.timeLimit(.minutes(1)))
struct ProjectBackgroundTests {
  static let found = "纳指回撤到二十日线。"

  static var agent: FakeAgent {
    FakeAgent(provider: .codex) { prompt in
      if prompt.hasPrefix(Background.lookInto) || prompt.hasPrefix(Background.followUp) { return .reply(found) }
      if prompt.hasPrefix("It is the end of") { return .reply("Done.") }
      return .reply("好")
    }
  }

  static func addSchedule(in project: Project.ID, on host: LocalHost) async throws -> ScheduleEntry {
    let reply = await Background.call(
      AddSchedule("nasdaq", Background.draft(.hour, follow: "看纳指")), from: .conversation(.project(project)), on: host)
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode(ScheduleEntry.self, from: data)
  }

  @Test func aProjectsScheduleRunsInTheProjectAndIsToldOnlyThere() async throws {
    try await withHost(agent: Self.agent) { host, place, world in
      let project = try await ProjectScenarioTests.start(host)
      let entry = try await Self.addSchedule(in: project, on: host)

      world.advance(minutes: 60)
      world.tick()

      let run = try #require(await Background.runs(of: entry.ref, on: host, where: Background.finished)?.first)
      #expect(run.record.hasPrefix("projects/\(project)/runs/"))
      #expect(run.kind.home == .project(project))
      let opened = try #require(
        world.agent.opened.first { $0.environment[LocalCall.sessionVariable]?.hasPrefix("run/") == true })
      #expect(opened.workingDirectory == place.store.home(.project(project)).folder)

      _ = try await host.run(SendMessage(to: .main, text: "后台做了什么"))
      _ = try #require(await settled(host))
      #expect(world.agent.prompts.last?.contains(Self.found) == false)

      _ = try await host.run(SendMessage(to: .project(project), text: "后台做了什么"))
      _ = try #require(await settled(host, .project(project), prompts: 2))
      let told = try #require(world.agent.prompts.last)
      #expect(told.contains(Self.found) && told.contains("(runs/"))
    }
  }

  @Test func aProjectsFollowUpIsToldItMayPutACardAndTheCardIsTheProjects() async throws {
    let agent = FakeAgent(provider: .codex) { prompt in
      if prompt.hasPrefix(Background.followUp) { return .hang }
      return .reply("好")
    }
    try await withHost(agent: agent) { host, place, world in
      let project = try await ProjectScenarioTests.start(host)
      let inProject = LocalSession.conversation(.project(project))
      _ = await Background.call(AddFollowUp(.after(minutes: 2), "看看纳指，放一张卡"), from: inProject, on: host)
      world.advance(minutes: 2)
      world.tick()

      let run = try await Background.runSession(world)
      for _ in 0..<500 where Background.prompts(world, starting: Background.followUp).isEmpty {
        try await Task.sleep(for: .milliseconds(10))
      }
      let prompt = try #require(world.agent.prompts.last { $0.hasPrefix(Background.followUp) })
      #expect(prompt.contains("next add"))
      #expect(world.agent.opened.last?.workingDirectory == place.store.home(.project(project)).folder)
      let card = await Background.call(AddNextUp("纳指回撤到二十日线", asking: "要加仓吗"), from: .run(run), on: host)
      guard case .value(let data)? = card else { throw HostError.invalidRequest("\(String(describing: card))") }
      #expect(try JSONDecoder().decode(NextUp.self, from: data).home == .project(project))
      #expect(try await host.nextUps(of: .project(project)).map(\.what) == ["纳指回撤到二十日线"])
      #expect(try await host.nextUps(of: .chat).map(\.what) == ["纳指回撤到二十日线"])
    }
  }

  @Test func whatAProjectsFollowUpFoundIsToldOnlyInTheProject() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let inProject = LocalSession.conversation(.project(project))
      _ = await Background.call(AddFollowUp(.after(minutes: 2), "看看纳指"), from: inProject, on: host)
      world.advance(minutes: 2)
      world.tick()
      for _ in 0..<500 where Background.prompts(world, starting: Background.followUp).isEmpty {
        try await Task.sleep(for: .milliseconds(10))
      }
      _ = await value(host.subscribe(LociWorking())) { $0.work == nil }

      _ = try await host.run(SendMessage(to: .main, text: "后台做了什么"))
      _ = try #require(await settled(host))
      #expect(world.agent.prompts.last?.contains(Self.found) == false)
      _ = try await host.run(SendMessage(to: .project(project), text: "后台做了什么"))
      _ = try #require(await settled(host, .project(project), prompts: 2))
      #expect(world.agent.prompts.last?.contains(Self.found) == true)
    }
  }

  @Test func aFollowUpThatFinishesSaysWhatItFoundInItsConversationAtOnce() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      _ = await Background.call(
        AddFollowUp(.after(minutes: 2), "看看纳指"), from: .conversation(.project(project)), on: host)
      _ = await Background.call(AddFollowUp(.after(minutes: 2), "看看日元"), from: .conversation(.main), on: host)
      world.advance(minutes: 2)
      world.tick()

      let told = { @Sendable (conversation: ConversationRef) in
        ((try? host.database.messages(of: .conversation(conversation))) ?? []).filter { $0.body == .told(Self.found) }
      }
      for _ in 0..<500 where told(.project(project)).isEmpty || told(.main).isEmpty {
        try await Task.sleep(for: .milliseconds(10))
      }

      #expect(told(.project(project)).count == 1)
      #expect(told(.main).count == 1)
    }
  }

  @Test func aScheduleAndAFollowUpThatFailedSayNothingInTheConversation() async throws {
    let agent = FakeAgent(provider: .codex) { prompt in
      if prompt.hasPrefix(Background.lookInto) { return .reply(Self.found) }
      if prompt.hasPrefix(Background.followUp) { return .fail("no network") }
      return .reply("好")
    }
    try await withHost(agent: agent) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let entry = try await Self.addSchedule(in: project, on: host)
      _ = await Background.call(
        AddFollowUp(.after(minutes: 60), "看看纳指"), from: .conversation(.project(project)), on: host)
      world.advance(minutes: 60)
      world.tick()
      _ = try #require(await Background.runs(of: entry.ref, on: host, where: Background.finished)?.first)
      for _ in 0..<500 where try host.database.openEvents().contains(where: { $0.source.home == .project(project) }) {
        world.advance(minutes: 20)
        world.tick()
        try await Task.sleep(for: .milliseconds(20))
      }

      let messages = try host.database.messages(of: .conversation(.project(project)))
      #expect(!messages.contains { if case .told = $0.body { true } else { false } })
    }
  }

  static func id(_ seed: UInt64) -> EntityID {
    var entropy = SeededGenerator(seed: seed)
    return EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + Double(seed)), entropy: &entropy)
  }

  @Test func eventsOfDifferentHomesNeverShareARun() {
    let due = Timestamp(millisecondsSince1970: 1_763_337_600_000)
    let chat = Event(id: Self.id(1), source: .schedule(Self.id(2), project: nil), due: due)
    let other = Event(id: Self.id(3), source: .schedule(Self.id(4), project: Self.id(40)), due: due)
    let same = Event(id: Self.id(5), source: .schedule(Self.id(6), project: nil), due: due)
    let followUp = Event(id: Self.id(7), source: .followUp(Self.id(8), project: nil), due: due)

    #expect(Worker.together([chat, other, same, followUp], first: chat) == [chat, same])
    #expect(Worker.together([followUp, chat, same], first: followUp) == [followUp])
  }

  @Test func anArchivedProjectsSchedulesDoNotComeDue() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      _ = try await Self.addSchedule(in: project, on: host)
      _ = try await host.run(ArchiveProject(project, archived: true))

      world.advance(minutes: 60)
      world.tick()
      try await Background.quiet()

      #expect(Background.prompts(world, starting: Background.lookInto).isEmpty)
      #expect(try host.database.openEvents().isEmpty)
    }
  }

  @Test func aProjectIsLookedBackOnWithOnlyItsOwnTranscriptsAndMemory() async throws {
    try await withHost(agent: Self.agent) { host, place, world in
      world.set(to: "22:00")
      let project = try await ProjectScenarioTests.start(host)
      world.set(to: "23:30")

      world.tick()

      for _ in 0..<500 where world.agent.prompts.filter({ $0.hasPrefix("It is the end of") }).count < 2 {
        try await Task.sleep(for: .milliseconds(10))
      }
      let reviews = world.agent.prompts.filter { $0.hasPrefix("It is the end of") }
      let ofProject = try #require(reviews.first { $0.contains("in the project") })
      let ofChat = try #require(reviews.first { !$0.contains("in the project") })
      #expect(ofProject.contains("`conversations/2025-11-17/projects-\(project)-"))
      #expect(!ofChat.contains("projects-\(project)"))
      let opened = world.agent.opened.filter { $0.workingDirectory == place.store.home(.project(project)).folder }
      #expect(opened.count >= 2)
      _ = await value(host.subscribe(LociWorking())) { $0.work == nil }
      #expect(!place.store.home(.project(project)).memoryIsWritable)
    }
  }

  @Test func aProjectKeptOutOfMemoryIsNotLookedBackOn() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      world.set(to: "22:00")
      let project = try await ProjectScenarioTests.start(host)
      _ = try await host.run(SetProjectRemembered(project, remembered: false))
      world.set(to: "23:30")

      world.tick()
      for _ in 0..<300 where world.agent.prompts.filter({ $0.hasPrefix("It is the end of") }).isEmpty {
        try await Task.sleep(for: .milliseconds(10))
      }
      try await Background.quiet()

      #expect(!world.agent.prompts.contains { $0.hasPrefix("It is the end of") && $0.contains("in the project") })
    }
  }
}
