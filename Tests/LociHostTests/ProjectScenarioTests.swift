import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// PJ-S2–PJ-S4, PJ-S7–PJ-S12: a project is a conversation of its own, with its own panels and folder, that the
/// main conversation knows only by a line. The companion runs on Codex.
@Suite(.timeLimit(.minutes(1)))
struct ProjectScenarioTests {
  static let words = "建一个投资项目，盯纳指和我的几只基金"

  static var agent: FakeAgent { FakeAgent(provider: .codex) }

  /// Starts a project and waits for its first turn to end, then names it as the companion would.
  static func start(_ host: LocalHost, named name: String = "投资", summary: String = "盯纳指和几只基金")
    async throws -> Project.ID
  {
    let project = try await host.run(StartProject(words)).id
    _ = try #require(await settled(host, .project(project)))
    let session = LocalSession.conversation(.project(project))
    _ = await Background.call(NameProject(name), from: session, on: host)
    _ = await Background.call(DescribeProject(summary), from: session, on: host)
    return project
  }

  static func bar(_ host: LocalHost, where match: @escaping @Sendable (ProjectBar) -> Bool) async -> ProjectBar? {
    await value(host.subscribe(WatchProjects()), where: match)
  }

  @Test func startingAProjectSaysTheWordsInItsOwnFolderAndTheCompanionNamesIt() async throws {
    try await withHost(agent: Self.agent) { host, place, world in
      let project = try await host.run(StartProject(Self.words))
      #expect(project.name == nil)
      _ = try #require(await settled(host, .project(project.id)))
      let folder = place.store.home(.project(project.id)).folder

      #expect(world.agent.opened.last?.workingDirectory == folder)
      let prompt = try #require(world.agent.prompts.last)
      #expect(prompt.typed.hasPrefix("This is a new project") && prompt.typed.hasSuffix(Self.words))
      let instructions = place.store.home(.project(project.id)).instructions()
      #expect(instructions.contains("# This project") && instructions.contains("agent/projects/\(project.id)/"))
      #expect(instructions.contains("../../../library/"))

      _ = await Background.call(NameProject("投资"), from: .conversation(.project(project.id)), on: host)

      let bar = try #require(await Self.bar(host) { $0.projects.map(\.name) == ["投资"] })
      #expect(bar.projects.first?.seal == "投")
    }
  }

  @Test func aProjectLeftUnnamedTakesItsFirstWords() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let project = try await host.run(StartProject(Self.words))

      let bar = try #require(await Self.bar(host) { !$0.projects.isEmpty })

      #expect(bar.projects.map(\.id) == [project.id])
      #expect(bar.projects.first?.name == "建一个投资项")
    }
  }

  @Test func lociProjectNameIsRefusedOutsideAProject() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let reply = await Background.call(NameProject("投资"), from: .conversation(.main), on: host)

      #expect(reply == .failed(.invalidRequest(NameProject.outside)))
    }
  }

  @Test func wordsInAProjectNeverReachTheMainConversationWhichKnowsOnlyItsLine() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      let project = try await Self.start(host)
      _ = try await host.run(SendMessage(to: .project(project), text: "纳指今天跌了多少"))
      _ = try #require(await settled(host, .project(project), prompts: 2))

      _ = try await host.run(SendMessage(to: .main, text: "我们最近在忙什么"))
      let main = try #require(await settled(host))

      #expect(main.messages.filter(\.isTyped).count == 1)
      let prompt = try #require(world.agent.prompts.last)
      #expect(prompt.contains("- 投资 (projects/\(project)): 盯纳指和几只基金"))
      #expect(!prompt.contains("纳指今天跌了多少"))
    }
  }

  @Test func aProjectSessionReadsTheMainIndexAndKeepsItsOwnNotes() async throws {
    let agent = FakeAgent(provider: .codex) { prompt in
      prompt.hasSuffix("记一下") ? .write(["notes/2025-11-17.md": "- 10:00 [x] 想加仓\n"], reply: "记了") : .reply("好")
    }
    try await withHost(agent: agent) { host, place, world in
      let project = try await Self.start(host)
      _ = try await host.run(SendMessage(to: .project(project), text: "记一下"))
      _ = try #require(await settled(host, .project(project), prompts: 2))
      _ = try await host.run(SendMessage(to: .project(project), text: "还记得吗"))
      _ = try #require(await settled(host, .project(project), prompts: 3))

      let prompt = try #require(world.agent.prompts.last)
      #expect(world.agent.prompts.contains { $0.contains("../../MEMORY.md:") && $0.contains("\nMEMORY.md:") })
      #expect(prompt.contains("想加仓"))
      #expect(prompt.contains("Conversation: in the project projects/\(project)"))
      let day = try #require(Day("2025-11-17"))
      #expect(try place.store.home(.chat).dayNotes(of: day).isEmpty)
      #expect(try place.store.home(.project(project)).dayNotes(of: day).contains("想加仓"))
    }
  }

  @Test func aProjectWithANewReplyIsUnseenUntilOpened() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      let project = try await Self.start(host)
      world.advance(minutes: 1)
      _ = try await host.run(SeeProject(project))
      _ = try #require(await Self.bar(host) { $0.unseen.isEmpty })

      world.advance(minutes: 1)
      _ = try await host.run(SendMessage(to: .project(project), text: "看看"))
      _ = try #require(await settled(host, .project(project), prompts: 2))

      _ = try #require(await Self.bar(host) { $0.unseen == [project] })
      world.advance(minutes: 1)
      _ = try await host.run(SeeProject(project))
      _ = try #require(await Self.bar(host) { $0.unseen.isEmpty })
    }
  }

  @Test func renamingAProjectChangesItsSeal() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let project = try await Self.start(host)

      let renamed = try await host.run(RenameProject(project, to: "Nasdaq"))

      #expect(renamed.seal == "N")
      await #expect(throws: HostError.self) { try await host.run(RenameProject(project, to: "  ")) }
    }
  }

  @Test func aProjectKeptOutOfMemoryIsNotToldToTheChatNorRecalledElsewhere() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      let project = try await Self.start(host)
      _ = try await host.run(SetProjectRemembered(project, remembered: false))

      _ = try await host.run(SendMessage(to: .main, text: "在忙什么"))
      _ = try #require(await settled(host))
      #expect(world.agent.prompts.last?.contains("projects/\(project)") == false)

      let fromMain = await Background.call(Recall("几只基金"), from: .conversation(.main), on: host)
      let inProject = await Background.call(Recall("几只基金"), from: .conversation(.project(project)), on: host)
      #expect(try Self.hits(fromMain).isEmpty)
      #expect(try Self.hits(inProject).map(\.path).allSatisfy { $0.hasPrefix("conversations/") })
      #expect(try !Self.hits(inProject).isEmpty)
    }
  }

  @Test func theChatNeverRecallsAProjectsWordsNorAProjectTheChats() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let project = try await Self.start(host)
      _ = try await host.run(SendMessage(to: .project(project), text: "项目口令是蓝玻璃四九三"))
      _ = try #require(await settled(host, .project(project), prompts: 2))
      _ = try await host.run(SendMessage(to: .main, text: "主对话口令是红陶罐"))
      _ = try #require(await settled(host))

      let fromMain = await Background.call(Recall("蓝玻璃四九三"), from: .conversation(.main), on: host)
      let chatsFromProject = await Background.call(Recall("红陶罐"), from: .conversation(.project(project)), on: host)
      let ownFromProject = await Background.call(
        Recall("蓝玻璃四九三"), from: .conversation(.project(project)), on: host)

      #expect(try Self.hits(fromMain).isEmpty)
      #expect(try Self.hits(chatsFromProject).isEmpty)
      #expect(try !Self.hits(ownFromProject).isEmpty)
    }
  }

  static func hits(_ reply: LocalReply?) throws -> [RecallHit] {
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode([RecallHit].self, from: data)
  }

  @Test func anArchivedProjectFoldsAwayAndComesBack() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let project = try await Self.start(host)

      _ = try await host.run(ArchiveProject(project, archived: true))
      let archived = try #require(await Self.bar(host) { $0.projects.isEmpty })
      #expect(archived.archived.map(\.id) == [project])

      _ = try await host.run(ArchiveProject(project, archived: false))
      _ = try #require(await Self.bar(host) { $0.projects.map(\.id) == [project] })
    }
  }

  @Test func deletingAProjectTakesItAllAndUndoBringsItBack() async throws {
    try await withHost(agent: Self.agent) { host, place, _ in
      let project = try await Self.start(host)
      _ = try await host.run(SavePanel(PanelScenarioTests.panel("holdings"), in: .project(project)))

      _ = try await host.run(DeleteProject(project))

      _ = try #require(await Self.bar(host) { $0.projects.isEmpty })
      await #expect(throws: HostError.self) { try await host.conversation(.project(project)) }
      let back = try await host.run(RestoreDeletedProject())
      #expect(back?.id == project)
      #expect(try await host.conversation(.project(project)).messages.contains { $0.isTyped })
      #expect(place.store.home(.project(project)).panels().map(\.name) == ["holdings"])
    }
  }

  @Test func theNextDeletionDiscardsTheLastProjectForGood() async throws {
    try await withHost(agent: Self.agent) { host, place, _ in
      let first = try await Self.start(host, named: "投资")
      let second = try await Self.start(host, named: "旅行")

      _ = try await host.run(DeleteProject(first))
      _ = try await host.run(DeleteProject(second))

      #expect(place.store.setAsideProjects() == [second])
      #expect(try host.database.messages(of: .conversation(.project(first))).isEmpty)
      #expect(try await host.run(RestoreDeletedProject())?.id == second)
      #expect(try await host.run(RestoreDeletedProject()) == nil)
    }
  }

  @Test func aPinnedPanelShowsInTheChatsColumnAsTheSamePanel() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let project = try await Self.start(host)
      let panel = PanelScenarioTests.panel("holdings", title: "持仓")
      _ = try await host.run(SavePanel(panel, in: .project(project)))
      #expect(try await host.panelColumn(of: .chat).slots.isEmpty)

      _ = try await host.run(PinPanel("holdings", of: project, pinned: true))
      #expect(try await host.panelColumn(of: .chat).slots == [.pinned(project, panel)])
      #expect(try await host.panelColumn(of: .project(project)).slots == [.panel(panel)])

      _ = try await host.run(PinPanel("holdings", of: project, pinned: false))
      #expect(try await host.panelColumn(of: .chat).slots.isEmpty)
    }
  }
}
