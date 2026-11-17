import LociModel
import Testing

@testable import LociHost

/// Changing a mentor to ask first applies to its very next tool, not to its next session.
@Suite(.timeLimit(.minutes(1)))
struct PermissionChangeTests {
  private func ask(_ mentor: Mentor) -> SetMentorAgent {
    SetMentorAgent(
      mentor: mentor.id, choice: AgentChoice(provider: mentor.provider, model: mentor.model), permission: .ask)
  }

  @Test func anIdleFullAccessSessionIsClosedAsSoonAsTheMentorMustAsk() async throws {
    try await withManualHost { host, _, _, agent in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let conversation = host.subscribe(MentorConversation(mentor: mentor.id))
      _ = try #require(await value(conversation) { $0.turn == nil && !$0.messages.isEmpty })
      let full = try #require(await agent.sessions.first)
      #expect(await agent.opened.first?.permission == .full)

      _ = try await host.run(ask(mentor))

      #expect(await full.closed)
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Run printf"))
      _ = try #require(await value(conversation) { $0.turn?.messages.count == 2 })
      #expect(await agent.opened.last?.permission == .ask)
      _ = try await host.run(StopTurn(mentor: mentor.id))
    }
  }

  @Test func aTurnRunningWithFullAccessStopsWhenTheMentorMustAsk() async throws {
    try await withManualHost { host, _, _, agent in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let conversation = host.subscribe(MentorConversation(mentor: mentor.id))
      _ = try #require(await value(conversation) { $0.turn == nil && !$0.messages.isEmpty })
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Run printf, then more"))
      _ = try #require(await value(conversation) { $0.turn?.messages.count == 2 })
      let full = try #require(await agent.sessions.first)

      _ = try await host.run(ask(mentor))

      let stopped = try await host.conversation(of: mentor.id)
      #expect(stopped.turn == nil)
      #expect(stopped.messages.last?.body == .ended(.interrupted))
      #expect(await full.closed)
    }
  }
}
