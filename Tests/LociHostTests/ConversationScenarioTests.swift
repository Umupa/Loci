import Foundation
import LociModel
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct ConversationScenarioTests {
  private static let quiet = FakeAgent { prompt in
    prompt.contains("new mentor") ? .reply("Ready.") : .reply("Hello there.")
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
      _ = await settled(host, mentor.id)
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

  /// α2-S6: a command runs only after the person allows it.
  @Test(arguments: [("allow", true), ("deny", false)])
  func aCommandRunsOnlyWhenAllowed(choice: String, runs: Bool) async throws {
    let agent = FakeAgent { prompt in prompt == "Run it" ? .askToRun : .reply("Ready.") }
    try await withHost(agent: agent) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)
      let feed = host.subscribe(MentorConversation(mentor: mentor.id))

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Run it"))
      let asking = try #require(await value(feed) { $0.turn?.waiting.isEmpty == false })
      let ask = try #require(asking.turn?.waiting.first)
      #expect(ask.options.map(\.role) == [.allow, .deny])
      #expect(asking.turn?.latestTool?.subject == "echo hi")
      _ = try await host.run(AnswerPermission(mentor: mentor.id, request: ask.id, answer: .chosen(choice)))

      let done = try #require(await settled(host, mentor.id, turns: 2))
      let tool = done.messages.compactMap { if case .tool(let tool) = $0.body { tool } else { nil } }.last
      #expect(tool?.state == (runs ? .succeeded : .failed))
      let answered = done.messages.compactMap { if case .permission(let ask) = $0.body { ask.answer } else { nil } }
      #expect(answered == [.chosen(choice)])
    }
  }

  /// α2-S7: stopping ends the turn, and the conversation goes on.
  @Test func stoppingEndsTheTurnAndTheConversationGoesOn() async throws {
    let agent = FakeAgent { prompt in prompt == "Take your time" ? .hang : .reply("Ready.") }
    try await withHost(agent: agent) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)
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
    _ = await settled(second, mentor.id, turns: 2)
    await second.close()

    #expect(after.messages == before?.messages)
    #expect(agent.opened.last?.resume?.value == "fake-1")
  }

  @Test func aMentorWhoseAgentIsMissingSaysSo() async throws {
    try await withHost { host, place, world in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)
      let grok = try Mentor(
        id: mentor.id, name: mentor.name, avatar: mentor.avatar, color: mentor.color, provider: .grok,
        permission: .full)
      try place.store.save(grok)

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Hi"))

      let failed = await settled(host, mentor.id, turns: 2)
      #expect(bodies(failed).last == .ended(.failed("grok is not installed on this Mac.")))
    }
  }

  @Test func deletingAMentorDeletesItsConversation() async throws {
    try await withHost(agent: Self.quiet) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)

      _ = try await host.run(DeleteMentor(mentor: mentor.id, notes: .delete))

      await #expect(throws: HostError.self) { try await host.conversation(of: mentor.id) }
    }
  }
}
