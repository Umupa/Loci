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
      let defaults = try await host.run(ReadAgentDefaults())

      #expect(defaults.forNewMentors == AgentChoice(provider: .pi))
    }
  }

  /// UI-S10: a new mentor runs on the default agent with that agent's default model.
  @Test func aNewMentorRunsOnTheDefaultAgentAndItsModel() async throws {
    try await withHost { host, place, world in
      _ = try await host.run(SetDefaultModel(provider: .grok, model: "grok-4"))
      _ = try await host.run(SetDefaultModel(provider: .pi, model: " deepseek-v4 "))
      let defaults = try await host.run(SetDefaultAgent(.pi))

      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)

      #expect(defaults.models == [.pi: "deepseek-v4", .grok: "grok-4"])
      #expect(mentor.provider == .pi)
      #expect(mentor.model == "deepseek-v4")
      #expect(world.agent.opened.last?.model == "deepseek-v4")
      #expect(try place.store.settings().agent == .pi)
    }
  }

  @Test func clearingADefaultModelLeavesTheChoiceToTheAgent() async throws {
    try await withHost { host, _, _ in
      _ = try await host.run(SetDefaultModel(provider: .pi, model: "deepseek-v4"))

      let defaults = try await host.run(SetDefaultModel(provider: .pi, model: nil))

      #expect(defaults.models[.pi] == nil)
    }
  }

  @Test func changingTheDefaultLeavesExistingMentorsAlone() async throws {
    try await withHost { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)

      _ = try await host.run(SetDefaultAgent(.grok))

      #expect(try await host.run(ListMentors()).first?.provider == .pi)
    }
  }

  /// UI-S8: a mentor's next turn runs with the model and thinking effort chosen beside the input field.
  @Test func aMentorsNextTurnRunsWithItsNewModelAndEffort() async throws {
    try await withHost { host, place, world in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)

      let changed = try await host.run(
        SetMentorAgent(mentor: mentor.id, choice: AgentChoice(provider: .pi, model: "m2", effort: .high)))
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Hi"))
      _ = await settled(host, mentor.id, turns: 2)

      #expect(changed.effort == .high)
      #expect(try place.store.mentor(mentor.id).model == "m2")
      #expect(world.agent.opened.last?.model == "m2")
      #expect(world.agent.opened.last?.effort == .high)
      #expect(world.agent.opened.count == 2)
    }
  }

  @Test func anEffortTheAgentDoesNotOfferIsDropped() async throws {
    try await withHost { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)

      let changed = try await host.run(
        SetMentorAgent(mentor: mentor.id, choice: AgentChoice(provider: .grok, effort: .high)))

      #expect(changed.effort == nil)
    }
  }

  /// The lesson language chosen in the settings is what the mentor is told to write in.
  @Test func aChosenLessonLanguageIsInTheMentorsFirstPrompt() async throws {
    try await withHost { host, _, world in
      _ = try await host.run(SetLessonLanguage(.fixed("zh-Hans")))

      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await settled(host, mentor.id)

      #expect(try await host.run(ReadLessonLanguage()) == .fixed("zh-Hans"))
      #expect(world.agent.prompts.first?.contains("`zh-Hans`") == true)
    }
  }

  @Test func theDataLocationIsTheHostsFolder() async throws {
    try await withHost { host, place, _ in
      let location = try await host.run(DataLocation())

      #expect(location == place.root)
    }
  }

  @Test func changingAnUnknownMentorIsRefused() async throws {
    try await withHost { host, _, world in
      await #expect(throws: HostError.self) {
        try await host.run(
          SetMentorAgent(mentor: world.nextID(), choice: AgentChoice(provider: .pi)))
      }
    }
  }
}
