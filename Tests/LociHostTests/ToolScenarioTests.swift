import Foundation
import LociAgents
import LociModel
import LociRemote
import Testing

@testable import LociHost

/// L-S12: Loci puts things into the library with the `loci` command.
@Suite(.timeLimit(.minutes(1)))
struct ToolScenarioTests {
  private actor Replies {
    var all: [LocalReply] = []
    func add(_ reply: LocalReply) { all.append(reply) }
  }

  /// The replies the gateway sends to one call.
  private func answer(_ call: LocalCall, on host: LocalHost) async -> [LocalReply] {
    let replies = Replies()
    await ToolGateway.answer(call, on: host) { await replies.add($0) }
    return await replies.all
  }

  private func command<C: Command>(_ command: C, in session: LocalSession? = .conversation(.main)) throws -> LocalCall {
    LocalCall(session: session, request: .command(name: C.name, body: try JSONEncoder().encode(command)))
  }

  private func item(_ replies: [LocalReply]) throws -> Item {
    guard case .value(let data) = try #require(replies.first) else {
      Issue.record("expected an item, got \(replies)")
      throw HostError.invalidRequest("no item")
    }
    return try JSONDecoder().decode(Item.self, from: data)
  }

  @Test func savingALinkShowsInTheTurnLociSavedItIn() async throws {
    try await withManualHost { host, _, _, agent in
      _ = try await host.run(SendMessage(to: .main, text: "Save this for me"))
      #expect(await working(host))
      let url = try #require(URL(string: "https://example.com/borg"))

      let saved = try item(await answer(try command(AddLink(url: url)), on: host))

      let shown = await value(host.subscribe(OneConversation(.main))) { conversation in
        conversation.turn?.messages.contains { $0.body == .savedItem(saved.id) } == true
      }
      #expect(shown != nil)
      await agent.sessions.first?.finish()
      let settledConversation = try #require(await settled(host))
      #expect(settledConversation.bodies.contains(.savedItem(saved.id)))
    }
  }

  @Test func onlyWhatThePersonSavedIsNewContextAndOnlyWhatLociSavedAppearsInChat() async throws {
    try await withManualHost { host, _, world, agent in
      _ = try await host.run(SendMessage(to: .main, text: "Write it up"))
      #expect(await working(host))
      world.advance(minutes: 1)

      let byLoci = try item(
        await answer(
          try command(AddTextItem(fileName: "notes.md", text: "# Borg\n", authors: [Item.companionCredit])), on: host))
      _ = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n"))
      await agent.sessions.first?.finish()
      let conversation = try #require(await settled(host))
      #expect(conversation.bodies.contains(.savedItem(byLoci.id)))
      #expect(conversation.entries.count == conversation.bodies.count)
      _ = try await host.run(SendMessage(to: .main, text: "Next"))
      #expect(await working(host))
      let told = try #require(await agent.sessions.first?.prompts.last)
      #expect(told.contains("\"Raft\""))
      #expect(!told.contains("\"Borg\""))
    }
  }

  @Test func savingInAnItemsConversationShowsThere() async throws {
    try await withManualHost { host, _, _, agent in
      let open = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n"))
      _ = try await host.run(SendMessage(to: .item(open.id), text: "Find the paper"))
      #expect(await working(host, .item(open.id)))
      let url = try #require(URL(string: "https://example.com/raft.pdf"))

      let saved = try item(await answer(try command(AddLink(url: url), in: .conversation(.item(open.id))), on: host))

      await agent.sessions.first?.finish()
      let conversation = try #require(await settled(host, .item(open.id)))
      #expect(conversation.bodies.contains(.savedItem(saved.id)))
      #expect(try await host.conversation(.main).bodies.allSatisfy { $0 != .savedItem(saved.id) })
    }
  }

  @Test func anArticleTheCompanionWroteHasItsAuthorCreditAndNoSource() async throws {
    try await withHost { host, _, _ in
      let saved = try item(
        await answer(
          try command(
            AddTextItem(fileName: "a.md", text: "# Old\n", title: "Borg in brief", authors: [Item.companionCredit])),
          on: host))

      #expect(saved.title == "Borg in brief")
      #expect(saved.authors == ["Companion"])
      #expect(saved.source == nil)
    }
  }

  @Test func onlyTheCommandsLociNeedsAreOpen() async throws {
    try await withHost { host, _, _ in
      let item = try await host.run(AddTextItem(fileName: "a.md", text: "# A\n"))

      let deleting = await answer(try command(DeleteItems([item.id])), on: host)
      let following = await answer(
        LocalCall(
          session: nil, request: .follow(name: AllItems.name, body: try JSONEncoder().encode(AllItems()))),
        on: host)

      #expect(deleting == [.failed(.invalidRequest("loci cannot run \(DeleteItems.name)"))])
      #expect(following == [.failed(.invalidRequest("loci cannot follow \(AllItems.name)"))])
      #expect(try await host.run(ListItems()) == [item])
    }
  }

  @Test func anItemsFolderIsGivenFromLocisFolder() async throws {
    try await withHost { host, _, _ in
      let item = try await host.run(AddTextItem(fileName: "a.md", text: "# Borg\n"))

      let replies = await answer(LocalCall(session: nil, request: .itemFolder(item.id)), on: host)

      let expected = try JSONEncoder().encode("../library/borg-\(item.id)/")
      #expect(replies == [.value(expected)])
    }
  }

  @Test func theAppAnswersOnItsSocketAndWritesTheSkill() async throws {
    let place = Place()
    defer { place.remove() }
    let socket = URL(filePath: "/tmp/loci-\(UUID().uuidString.prefix(8))/loci.sock")
    defer { try? FileManager.default.removeItem(at: socket.deletingLastPathComponent()) }
    let world = TestWorld()
    let environment = world.environment(
      running: { _ in nil },
      tool: AgentTool(folder: URL(filePath: "/Applications/Loci.app/Contents/Helpers"), socket: socket))
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: environment)
    _ = try await host.run(AddTextItem(fileName: "a.md", text: "# 调度\n\n过滤与打分\n"))
    let call = LocalCall(
      session: nil, request: .command(name: Search.name, body: try JSONEncoder().encode(Search(text: "调度"))))

    var reply: LocalReply?
    for _ in 0..<100 where reply == nil {
      reply = try? await LocalSocket.call(call, at: socket)
      if reply == nil { try await Task.sleep(for: .milliseconds(20)) }
    }

    guard case .value(let data) = try #require(reply) else { throw HostError.invalidRequest("no hits") }
    #expect(try JSONDecoder().decode([SearchHit].self, from: data).isEmpty == false)
    let folder = try FileManager.default.attributesOfItem(atPath: socket.deletingLastPathComponent().path)
    #expect((folder[.posixPermissions] as? Int) == 0o700)
    let skill = place.root.appending(path: "agent/.claude/skills/loci/SKILL.md")
    #expect(try String(contentsOf: skill, encoding: .utf8) == ToolGuide.skill)
    let codexSkill = place.root.appending(path: "agent/.agents/skills/loci/SKILL.md")
    #expect(try String(contentsOf: codexSkill, encoding: .utf8) == ToolGuide.skill)
    await host.close()
  }

  @Test func eachConversationsSessionIsToldWhichConversationItIs() async throws {
    try await withManualHost { host, _, _, agent in
      let open = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n"))
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = try await host.run(SendMessage(to: .item(open.id), text: "Hi"))
      #expect(await working(host))
      #expect(await working(host, .item(open.id)))

      let told = await agent.opened.map { $0.environment[LocalCall.sessionVariable] }

      #expect(Set(told) == ["main", "library/\(open.id)"])
    }
  }

  @Test func lociSavesAndListsPanelsThroughTheGateway() async throws {
    try await withHost { host, _, _ in
      let saved = await answer(try command(SavePanel(PanelScenarioTests.radar), in: nil), on: host)
      let listed = await answer(try command(ListPanels(), in: nil), on: host)

      #expect(saved == [.value(try JSONEncoder().encode(Done()))])
      guard case .value(let data) = try #require(listed.first) else { return }
      #expect(try JSONDecoder().decode([PanelEntry].self, from: data).map(\.panel) == [PanelScenarioTests.radar])
      #expect(try await host.panelColumn(of: .chat).slots == [.panel(PanelScenarioTests.radar)])
    }
  }

  @Test func lociPanelSaveInAProjectsSessionSavesInTheProject() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, place, _ in
      let project = try await ProjectScenarioTests.start(host)
      let session = LocalSession.conversation(.project(project))

      _ = await answer(try command(SavePanel(PanelScenarioTests.radar), in: session), on: host)
      let listed = await answer(try command(ListPanels(), in: session), on: host)

      #expect(place.store.home(.project(project)).panels().map(\.panel) == [PanelScenarioTests.radar])
      #expect(place.store.home(.chat).panels().isEmpty)
      guard case .value(let data) = try #require(listed.first) else { return }
      #expect(try JSONDecoder().decode([PanelEntry].self, from: data).map(\.panel) == [PanelScenarioTests.radar])
      let folder = await answer(
        LocalCall(
          session: session, request: .itemFolder(try await host.run(AddTextItem(fileName: "a.md", text: "# Borg\n")).id)
        ),
        on: host)
      guard case .value(let path) = try #require(folder.first) else { return }
      #expect(try JSONDecoder().decode(String.self, from: path).hasPrefix("../../../library/"))
    }
  }
}

/// I-S10: what Loci saves with `loci save` while earlier saves still have work going on is one batch.
@Suite(.timeLimit(.minutes(1)))
struct SavingBatchTests {
  private func save(_ link: String, on host: LocalHost) async throws {
    let body = try JSONEncoder().encode(AddLink(url: Links.url(link)))
    await ToolGateway.answer(
      LocalCall(session: .conversation(.main), request: .command(name: AddLink.name, body: body)), on: host
    ) { _ in }
  }

  @Test func itemsLociSavesOneAfterAnotherFormOneBatch() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))
      world.programs.site(Links.bilibili, FakeSite(title: "Scheduling"))
      await world.programs.downloads.close()

      try await save(Links.youtube, on: host)
      try await save(Links.bilibili, on: host)

      let batch = await value(host.subscribe(SavingNow())) { $0?.items.count == 2 }
      #expect(batch??.finished == 0)
      _ = try await host.run(AddLink(url: Links.url(Links.episode)))
      #expect(await host.savingBatch()?.items.count == 2)
      await world.programs.downloads.open()
      #expect(await value(host.subscribe(SavingNow())) { $0 == nil } != nil)
    }
  }

  @Test func stoppingTheBatchDeletesTheItemsNotYetStartedAndUndoingBringsThemBack() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))
      world.programs.site(Links.bilibili, FakeSite(title: "Scheduling"))
      world.programs.site(Links.episode, FakeSite(title: "Episode", audio: true))
      await world.programs.downloads.close()
      try await save(Links.youtube, on: host)
      try await save(Links.bilibili, on: host)
      try await save(Links.episode, on: host)
      let settled = await until(within: .seconds(20)) {
        let jobs = (try? await host.run(ListJobs())) ?? []
        return world.programs.calls(with: "--print").count == 2 && jobs.count { $0.state == .queued } == 1
      }
      #expect(settled)
      let queued = try #require(try await host.run(ListJobs()).first { $0.state == .queued }?.item)

      #expect(try await host.run(StopSaving()) == 1)

      let items = try await host.run(ListItems())
      #expect(items.count == 2)
      #expect(!items.contains { $0.id == queued })
      _ = try await host.run(RestoreDeleted())
      #expect(try await host.run(ListItems()).count == 3)
    }
  }
}
