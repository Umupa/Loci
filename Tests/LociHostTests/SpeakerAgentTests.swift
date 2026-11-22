import LociModel
import Testing

@testable import LociHost

struct SpeakerAgentTests {
  @Test func speakerNamesUseOneSessionWithTheEpisodeDescriptionAndOpening() async throws {
    let driver = FakeAgent { _ in .reply(#"{"names": {"1": " Maya Chen ", "2": "", "9": "Unknown ID"}}"#) }
    let agent = AgentTranscriptAgent(runtime: Runtime(provider: .codex), agents: { $0 == .codex ? driver : nil })
    let transcript = try Transcript(
      language: "en", origin: .platform,
      segments: [
        try .init(start: .zero, end: .seconds(2), text: "I'm Maya.", speaker: 1),
        try .init(start: .seconds(2), end: .seconds(4), text: "Welcome.", speaker: 2),
        try .init(start: .seconds(150), end: .seconds(152), text: "Later.", speaker: 3),
      ])

    let names = try await agent.nameSpeakers(in: transcript, description: "A show with Maya Chen.")

    #expect(names == [1: "Maya Chen"])
    #expect(driver.opened.count == 1)
    #expect(driver.opened.first?.resume == nil)
    #expect(driver.prompts.count == 1)
    #expect(driver.prompts.first?.contains("A show with Maya Chen.") == true)
    #expect(driver.prompts.first?.contains("I'm Maya.") == true)
    #expect(driver.prompts.first?.contains("Later.") == false)
  }

  @Test func anUnusableSpeakerAnswerDoesNotSpendAnotherTurn() async throws {
    let driver = FakeAgent { _ in .reply("There isn't enough evidence.") }
    let agent = AgentTranscriptAgent(runtime: Runtime(provider: .codex), agents: { _ in driver })
    let transcript = try Transcript(
      language: nil, origin: .platform,
      segments: [try .init(start: .zero, end: .seconds(2), text: "Welcome.", speaker: 1)])

    let names = try await agent.nameSpeakers(in: transcript, description: nil)

    #expect(names.isEmpty)
    #expect(driver.prompts.count == 1)
  }
}
