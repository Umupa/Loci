import Foundation
import LociModel
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct AgentSettingsTests {
  private func settled(_ host: LocalHost, _ mentor: EntityID, turns: Int = 1) async -> Conversation? {
    await value(host.subscribe(MentorConversation(mentor: mentor))) { conversation in
      conversation.turn == nil
        && conversation.messages.count { if case .prompt = $0.body { true } else { false } } == turns
    }
  }

  /// α2-S10: the settings list what is installed on this Mac, and can look again.
  @Test func theSettingsSeeWhichAgentsAreInstalled() async throws {
    try await withHost { host, _, world in
      let found = try await host.run(DetectAgents())
      _ = try await host.run(DetectAgents(again: true))

      #expect(found == TestWorld.installed)
      #expect(world.lookedAgain == [false, true])
    }
  }

  @Test func withNothingChosenNewMentorsRunOnWhatTheHostStartedWith() async throws {
    try await withHost { host, _, _ in
      let choice = try await host.run(NewMentorAgent())

      #expect(choice == AgentChoice(provider: .pi))
    }
  }

  /// α2-S10: a new mentor runs on the agent and model chosen in the settings.
  @Test func aNewMentorRunsOnTheChosenAgentAndModel() async throws {
    try await withHost { host, place, world in
      _ = try await host.run(SetNewMentorAgent(AgentChoice(provider: .pi, model: " deepseek-v4 ")))

      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)

      #expect(mentor.provider == .pi)
      #expect(mentor.model == "deepseek-v4")
      #expect(world.agent.opened.last?.model == "deepseek-v4")
      #expect(try place.store.newMentorAgent() == AgentChoice(provider: .pi, model: "deepseek-v4"))
    }
  }

  @Test func changingTheChoiceLeavesExistingMentorsAlone() async throws {
    try await withHost { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)

      _ = try await host.run(SetNewMentorAgent(AgentChoice(provider: .grok)))

      #expect(try await host.run(ListMentors()).first?.provider == .pi)
    }
  }

  /// A mentor's own settings: the next turn runs with the new model and asks before acting.
  @Test func aMentorsNextTurnRunsWithItsNewSettings() async throws {
    try await withHost { host, place, world in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)

      let changed = try await host.run(
        SetMentorAgent(mentor: mentor.id, choice: AgentChoice(provider: .pi, model: "m2"), permission: .ask))
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Hi"))
      _ = await settled(host, mentor.id, turns: 2)

      #expect(changed.permission == .ask)
      #expect(try place.store.mentor(mentor.id).model == "m2")
      #expect(world.agent.opened.last?.model == "m2")
      #expect(world.agent.opened.last?.permission == .ask)
    }
  }

  @Test func changingAnUnknownMentorIsRefused() async throws {
    try await withHost { host, _, world in
      await #expect(throws: HostError.self) {
        try await host.run(
          SetMentorAgent(mentor: world.nextID(), choice: AgentChoice(provider: .pi), permission: .ask))
      }
    }
  }
}
