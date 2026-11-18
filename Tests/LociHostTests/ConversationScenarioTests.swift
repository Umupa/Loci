import Foundation
import LociModel
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct ConversationScenarioTests {
  private static var quiet: FakeAgent {
    FakeAgent { prompt in prompt.contains("new mentor") ? .reply("Ready.") : .reply("Hello there.") }
  }

  /// Waits for the mentor's first turn, which every new mentor starts with, to end.
  private func settled(_ host: LocalHost, _ mentor: EntityID, turns: Int = 1) async -> Conversation? {
    await value(host.subscribe(MentorConversation(mentor: mentor))) { conversation in
      conversation.turn == nil
        && conversation.messages.count { if case .prompt = $0.body { true } else { false } } == turns
    }
  }

  private func bodies(_ conversation: Conversation?) -> [Message.Body] {
    conversation?.messages.map(\.body) ?? []
  }

  /// α2-S6: the reply arrives in pieces into one message, and the conversation keeps it.
  @Test func aReplyStreamsIntoTheConversation() async throws {
    try await withHost(agent: Self.quiet) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))
      let feed = host.subscribe(MentorConversation(mentor: mentor.id))

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Hi"))

      let partial = await value(feed) { conversation in
        conversation.turn?.messages.contains { if case .reply(let text) = $0.body { text == "Hello" } else { false } }
          == true
      }
      #expect(partial != nil)
      let done = await settled(host, mentor.id, turns: 2)
      #expect(bodies(done).suffix(2) == [.prompt(Prompt(text: "Hi", purpose: .chat)), .reply("Hello there.")])
    }
  }

  @Test func aMessageWhileTheMentorWorksIsRefused() async throws {
    try await withHost(agent: FakeAgent { _ in .hang }) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))

      await #expect(throws: HostError.self) { try await host.run(SendMessage(mentor: mentor.id, text: "Hi")) }
      _ = try await host.run(StopTurn(mentor: mentor.id))
    }
  }

  /// UI-S10: every mentor runs with full access; an agent that still asks is allowed, and nothing waits on
  /// the person.
  @Test func aCommandTheAgentAsksAboutRunsWithoutAsking() async throws {
    let agent = FakeAgent { prompt in prompt == "Run it" ? .askToRun : .reply("Ready.") }
    try await withHost(agent: agent) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Run it"))

      let done = try #require(await settled(host, mentor.id, turns: 2))
      let tool = done.messages.compactMap { if case .tool(let tool) = $0.body { tool } else { nil } }.last
      #expect(tool?.state == .succeeded)
      #expect(bodies(done).last == .reply("It printed hi."))
    }
  }

  /// UI-S8: what the agent says about its context window is in the conversation.
  @Test func theContextUsageTheAgentReportsIsShown() async throws {
    try await withManualHost { host, _, _, agent in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Hi"))
      let session = try #require(await agent.sessions.last)

      await session.emit(.context(ContextUsage(used: 68_000, window: 200_000)))

      let reported = await value(host.subscribe(MentorConversation(mentor: mentor.id))) { $0.context != nil }
      #expect(reported?.context == ContextUsage(used: 68_000, window: 200_000))
      await session.finish()
    }
  }

  /// α2-S7: stopping ends the turn, and the conversation goes on.
  @Test func stoppingEndsTheTurnAndTheConversationGoesOn() async throws {
    let agent = FakeAgent { prompt in prompt == "Take your time" ? .hang : .reply("Ready.") }
    try await withHost(agent: agent) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Take your time"))

      _ = try await host.run(StopTurn(mentor: mentor.id))

      let stopped = await settled(host, mentor.id, turns: 2)
      #expect(bodies(stopped).last == .ended(.interrupted))
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Again"))
      #expect(bodies(await settled(host, mentor.id, turns: 3)).last == .reply("Ready."))
    }
  }

  /// α2-S8: after a restart the conversation is all there, and the agent's session is resumed.
  @Test func theConversationSurvivesARestart() async throws {
    let place = Place()
    defer { place.remove() }
    let agent = FakeAgent { _ in .reply("Ready.") }
    let world = TestWorld(agent: agent)
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let mentor = try await first.run(CreateMentor(request: "Scheduling"))
    let before = await settled(first, mentor.id)
    await first.close()

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let after = try await second.conversation(of: mentor.id)
    _ = try await second.run(SendMessage(mentor: mentor.id, text: "Still there?"))
    _ = try #require(await settled(second, mentor.id, turns: 2))
    await second.close()

    #expect(after.messages == before?.messages)
    #expect(agent.opened.last?.resume?.value == "fake-1")
  }

  /// UI-S11: `/new` starts over. Every message stays, a line marks the place, and the next message goes to
  /// an agent session that remembers nothing before it.
  @Test func startingOverKeepsTheMessagesAndTheNextMessageGoesToAFreshSession() async throws {
    let agent = FakeAgent { _ in .reply("Ready.") }
    try await withHost(agent: agent) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let before = try #require(await settled(host, mentor.id))

      _ = try await host.run(StartOver(mentor: mentor.id))
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Again"))

      let after = try #require(await settled(host, mentor.id, turns: 2))
      #expect(Array(after.messages.prefix(before.messages.count)) == before.messages)
      #expect(after.messages[before.messages.count].body == .startedOver)
      #expect(agent.opened.count == 2)
      #expect(agent.opened.last?.resume == nil)
    }
  }

  @Test func aConversationThatStartedOverStartsFreshAfterARestart() async throws {
    let place = Place()
    defer { place.remove() }
    let agent = FakeAgent { _ in .reply("Ready.") }
    let world = TestWorld(agent: agent)
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let mentor = try await first.run(CreateMentor(request: "Scheduling"))
    _ = await settled(first, mentor.id)
    _ = try await first.run(StartOver(mentor: mentor.id))
    await first.close()

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    _ = try await second.run(SendMessage(mentor: mentor.id, text: "Still there?"))
    let after = try #require(await settled(second, mentor.id, turns: 2))
    await second.close()

    #expect(after.messages.contains { $0.body == .startedOver })
    #expect(agent.opened.last?.resume == nil)
  }

  @Test func startingOverTwiceLeavesOneLine() async throws {
    try await withHost(agent: Self.quiet) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))

      _ = try await host.run(StartOver(mentor: mentor.id))
      _ = try await host.run(StartOver(mentor: mentor.id))

      let conversation = try await host.conversation(of: mentor.id)
      #expect(conversation.messages.count { $0.body == .startedOver } == 1)
    }
  }

  @Test func startingOverWhileTheMentorWorksIsRefused() async throws {
    try await withHost(agent: FakeAgent { _ in .hang }) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))

      await #expect(throws: HostError.self) { try await host.run(StartOver(mentor: mentor.id)) }
      _ = try await host.run(StopTurn(mentor: mentor.id))
    }
  }

  @Test func aMentorWhoseAgentIsMissingSaysSo() async throws {
    try await withHost { host, place, world in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))
      let grok = try Mentor(
        id: mentor.id, name: mentor.name, avatar: mentor.avatar, color: mentor.color, provider: .grok)
      try place.store.save(grok)

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Hi"))

      let failed = await settled(host, mentor.id, turns: 2)
      #expect(bodies(failed).last == .ended(.failed("grok is not installed on this Mac.")))
    }
  }

  @Test func deletingAMentorDeletesItsConversation() async throws {
    try await withHost(agent: Self.quiet) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))

      _ = try await host.run(DeleteMentor(mentor: mentor.id, notes: .delete))

      await #expect(throws: HostError.self) { try await host.conversation(of: mentor.id) }
    }
  }

  /// While a mentor is being deleted its files are still there, and a refresh then must not bring its
  /// conversation back.
  @Test func aMentorBeingDeletedGetsNoNewConversation() async throws {
    try await withHost(agent: Self.quiet) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))

      await host.mentors.forget(mentor.id)

      await #expect(throws: HostError.notFound(mentor.id.description)) { try await host.conversation(of: mentor.id) }
      await host.mentors.forgotten(mentor.id)
      #expect(try await host.conversation(of: mentor.id).messages.isEmpty)
    }
  }
}
