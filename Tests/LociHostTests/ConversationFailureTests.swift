import LociAgents
import LociModel
import LociStore
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct ConversationFailureTests {
  @Test func aMissingSavedSessionStartsAFreshOneAndKeepsTheHistory() async throws {
    try await withManualHost { host, _, world, agent in
      let instructions = try await host.loci.context.instructions()
      let old = SessionRecord(
        id: world.nextID(), owner: .conversation(.main), runtime: Runtime(provider: .pi), handle: "gone",
        instructions: Fingerprint.of(instructions), startedAt: TestWorld.instant)
      try host.database.start(old)
      let message = Message(id: world.nextID(), at: TestWorld.instant, body: .reply("Previous reply"))
      try host.database.append([message], to: old.id)

      _ = try await host.run(SendMessage(to: .main, text: "Again"))
      #expect(await working(host))
      #expect(await agent.opened.map { $0.resume?.value } == ["gone", nil])
      let session = try #require(await agent.sessions.last)
      #expect(await session.prompts.last?.contains("Loci: Previous reply") == true)
      await session.finish()
      let done = try #require(await settled(host))
      #expect(done.messages.first == message)
      let latest = try host.database.latestSession(of: .conversation(.main))
      #expect(latest?.id != old.id)
      #expect(latest?.handle == session.handle.value)
      #expect(try host.database.messages(of: .conversation(.main)) == done.messages)
    }
  }

  @Test func anAgentLaunchFailureIsStoredAsAFailedTurn() async throws {
    try await withManualHost(agent: ManualAgent(openingFailure: .cannotLaunch("missing executable"))) {
      host, _, _, agent in
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))

      let done = try #require(await settled(host))
      #expect(done.messages.last?.body == .ended(.unstarted(.pi, .notInstalled)))
      #expect(try host.database.messages(of: .conversation(.main)) == done.messages)
      #expect(try host.database.latestSession(of: .conversation(.main))?.handle == nil)
      #expect(await agent.opened.count == 1)
    }
  }

  @Test func anExitedAgentGetsANewSessionForTheNextMessage() async throws {
    try await withManualHost { host, _, _, agent in
      _ = try await host.run(SendMessage(to: .main, text: "Crash"))
      #expect(await working(host))
      let first = try #require(await agent.sessions.first)
      await first.finish(.failed(.exited(code: 9, diagnostics: "crashed")))
      #expect(await settled(host)?.messages.last?.body == .ended(.failed("crashed")))
      #expect(await first.closed)

      _ = try await host.run(SendMessage(to: .main, text: "Retry"))
      #expect(await working(host))
      #expect(await agent.sessions.count == 2)
      await agent.sessions.last?.finish()
      _ = await settled(host, prompts: 2)
    }
  }

  /// A request with an allow option is allowed; one without is dismissed, and neither shows in the turn.
  @Test func permissionRequestsAreAnsweredWithoutThePerson() async throws {
    try await withManualHost { host, _, _, agent in
      _ = try await host.run(SendMessage(to: .main, text: "Ask"))
      #expect(await working(host))
      let session = try #require(await agent.sessions.first)

      await session.emit(
        .permission(
          PermissionRequest(
            id: .init("ask"), title: "bash",
            options: [.init(id: "no", role: .deny), .init(id: "always", role: .allowAlways)])))
      await session.emit(.permission(PermissionRequest(id: .init("pick"), title: "which", options: [])))
      await session.finish()

      let done = try #require(await settled(host))
      #expect(await session.answers == [.chosen("always"), .dismissed])
      #expect(done.bodies == [.prompt(Prompt(text: "Ask", purpose: .chat)), .reply("Waiting")])
    }
  }

  @Test func idleStopsAddNothing() async throws {
    try await withHost { host, _, world in
      _ = try await host.run(StopTurn(in: .main))
      _ = try await host.run(StopTurn(in: .item(world.nextID())))

      #expect(try await host.conversation(.main).entries.isEmpty)
      #expect(world.agent.prompts.isEmpty)
    }
  }
}
