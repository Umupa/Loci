import LociAgents
import LociModel
import LociStore
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct ConversationFailureTests {
  private func idle(_ host: LocalHost, _ mentor: EntityID, prompts: Int = 1) async throws -> Conversation {
    try #require(
      await value(host.subscribe(MentorConversation(mentor: mentor))) {
        $0.turn == nil && $0.messages.count { if case .prompt = $0.body { true } else { false } } == prompts
      })
  }

  private func working(_ host: LocalHost, _ mentor: EntityID) async throws {
    let live = await value(host.subscribe(MentorConversation(mentor: mentor))) {
      $0.turn?.messages.contains { $0.body == .reply("Waiting") } == true
    }
    #expect(live != nil)
  }

  @Test func aMissingSavedSessionStartsAFreshConversationAndKeepsTheHistory() async throws {
    try await withManualHost { host, place, world, agent in
      let mentor = try Mentor(
        id: world.nextID(), name: "Scheduling", avatar: "owl", color: MentorColor.palette[0], provider: .pi)
      try place.store.create(mentor)
      let old = ConversationRecord(id: world.nextID(), mentor: mentor.id, provider: .pi, session: "gone")
      try host.database.start(old, at: TestWorld.instant)
      let message = Message(id: world.nextID(), at: TestWorld.instant, body: .reply("Previous reply"))
      try host.database.append([message], to: old.id)

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Again"))
      try await working(host, mentor.id)
      let attempts = await agent.opened
      #expect(attempts.map { $0.resume?.value } == ["gone", nil])
      let session = try #require(await agent.sessions.last)
      await session.finish()
      let done = try await idle(host, mentor.id)
      #expect(done.messages.first == message)
      #expect(try host.database.latestConversation(of: mentor.id)?.id != old.id)
      #expect(try host.database.latestConversation(of: mentor.id)?.session == session.handle.value)
      #expect(try host.database.messages(of: mentor.id) == done.messages)
    }
  }

  @Test func anAgentLaunchFailureIsStoredAsAFailedTurn() async throws {
    try await withManualHost(agent: ManualAgent(openingFailure: .cannotLaunch("missing executable"))) {
      host, _, _, agent in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let done = try await idle(host, mentor.id)
      #expect(done.messages.last?.body == .ended(.unstarted(.pi, .notInstalled)))
      #expect(try host.database.messages(of: mentor.id) == done.messages)
      #expect(try host.database.latestConversation(of: mentor.id)?.session == nil)
      #expect(await agent.opened.count == 1)
    }
  }

  @Test func anExitedAgentGetsANewSessionForTheNextMessage() async throws {
    try await withManualHost { host, _, _, agent in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try await idle(host, mentor.id)
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Crash"))
      try await working(host, mentor.id)
      let first = try #require(await agent.sessions.first)
      await first.finish(.failed(.exited(code: 9, diagnostics: "crashed")))
      #expect(try await idle(host, mentor.id, prompts: 2).messages.last?.body == .ended(.failed("crashed")))
      #expect(await first.closed)

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Retry"))
      try await working(host, mentor.id)
      #expect(await agent.sessions.count == 2)
      await agent.sessions.last?.finish()
      _ = try await idle(host, mentor.id, prompts: 3)
    }
  }

  /// A request with an allow option is allowed; one without is dismissed, and neither shows in the turn.
  @Test func permissionRequestsAreAnsweredWithoutThePerson() async throws {
    try await withManualHost { host, _, _, agent in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try await idle(host, mentor.id)
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Ask"))
      try await working(host, mentor.id)
      let session = try #require(await agent.sessions.first)

      await session.emit(
        .permission(
          PermissionRequest(
            id: .init("ask"), title: "bash",
            options: [.init(id: "no", role: .deny), .init(id: "always", role: .allowAlways)])))
      await session.emit(.permission(PermissionRequest(id: .init("pick"), title: "which", options: [])))
      await session.finish()

      let done = try await idle(host, mentor.id, prompts: 2)
      #expect(await session.answers == [.chosen("always"), .dismissed])
      #expect(done.messages.suffix(2).map(\.body) == [.prompt(Prompt(text: "Ask", purpose: .chat)), .reply("Waiting")])
    }
  }

  @Test func deletingABusyMentorClosesItsSessionAndRemovesPersistedMessages() async throws {
    try await withManualHost { host, _, _, agent in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try await idle(host, mentor.id)
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Keep working"))
      try await working(host, mentor.id)
      let session = try #require(await agent.sessions.first)

      _ = try await host.run(DeleteMentor(mentor: mentor.id, notes: .delete))

      #expect(await session.closed)
      #expect(try host.database.messages(of: mentor.id).isEmpty)
      #expect(try host.database.latestConversation(of: mentor.id) == nil)
      await #expect(throws: HostError.self) { try await host.run(SendMessage(mentor: mentor.id, text: "Again")) }
    }
  }

  @Test func blankMessagesAreRefusedAndIdleStopsDoNotAddMessages() async throws {
    try await withHost { host, _, world in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let before = try await idle(host, mentor.id)
      await #expect(throws: HostError.invalidRequest("the message is empty")) {
        try await host.run(SendMessage(mentor: mentor.id, text: " \n\t"))
      }
      _ = try await host.run(StopTurn(mentor: mentor.id))
      _ = try await host.run(StopTurn(mentor: mentor.id))
      #expect(try await host.conversation(of: mentor.id) == before)
      #expect(world.agent.prompts.count == 1)
    }
  }

  @Test func deletingAnUnopenedMentorAlsoDeletesItsSavedConversation() async throws {
    try await withHost { host, place, world in
      let mentor = try Mentor(
        id: world.nextID(), name: "Scheduling", avatar: "owl", color: MentorColor.palette[0], provider: .pi)
      try place.store.create(mentor)
      let conversation = ConversationRecord(id: world.nextID(), mentor: mentor.id, provider: .pi, session: "saved")
      try host.database.start(conversation, at: TestWorld.instant)
      try host.database.append(
        [Message(id: world.nextID(), at: TestWorld.instant, body: .reply("old"))], to: conversation.id)
      _ = try await host.run(DeleteMentor(mentor: mentor.id, notes: .delete))
      #expect(try host.database.messages(of: mentor.id).isEmpty)
      #expect(try host.database.latestConversation(of: mentor.id) == nil)
      #expect(world.agent.opened.isEmpty)
    }
  }
}
