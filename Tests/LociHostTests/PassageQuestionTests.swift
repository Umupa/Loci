import Foundation
import LociModel
import Testing

@testable import LociHost

/// UI-S6: asking about a passage happens in the conversation, and the answer is saved in the highlight.
@Suite(.timeLimit(.minutes(1)))
struct PassageQuestionTests {
  private static var agent: FakeAgent {
    FakeAgent { prompt in prompt.contains("new mentor") ? .reply("Ready.") : .reply("Because nodes differ.") }
  }

  private func settled(_ host: LocalHost, _ mentor: EntityID, turns: Int = 1) async -> Conversation? {
    await value(host.subscribe(MentorConversation(mentor: mentor))) { conversation in
      conversation.turn == nil
        && conversation.messages.count { if case .prompt = $0.body { true } else { false } } == turns
    }
  }

  private func passage(_ mentor: EntityID) throws -> Passage {
    Passage(
      locator: .lesson(LessonRef(mentor: mentor, lesson: Lesson.Slug("why-schedule")!), try TextQuote("Pods need")),
      excerpt: "Pods need a node.")
  }

  @Test func askingAboutAPassageShowsTheQuestionWithItsPassageInTheConversation() async throws {
    try await withHost(agent: Self.agent) { host, place, world in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))
      let passage = try passage(mentor.id)

      _ = try await host.run(SendMessage(mentor: mentor.id, text: " Why? ", passage: passage))

      let done = try #require(await settled(host, mentor.id, turns: 2))
      let note = try #require(place.store.notes(on: passage.locator.content).value.first)
      let asked = done.messages.compactMap { if case .prompt(let prompt) = $0.body { prompt } else { nil } }.last
      #expect(
        asked
          == Prompt(
            text: "Why?", purpose: .chat,
            passage: QuotedPassage(
              locator: passage.locator, excerpt: "Pods need a node.", note: note.id)))
      #expect(world.agent.prompts.last?.contains("> Pods need a node.") == true)
      #expect(world.agent.prompts.last?.hasSuffix("Why?") == true)
    }
  }

  @Test func theAnswerIsSavedInTheHighlightWhenTheTurnEnds() async throws {
    try await withHost(agent: Self.agent) { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))
      let passage = try passage(mentor.id)

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Why?", passage: passage))

      let done = try #require(await settled(host, mentor.id, turns: 2))
      let note = try #require(place.store.notes(on: passage.locator.content).value.first)
      #expect(note.excerpt == "Pods need a node.")
      #expect(note.exchanges.map(\.question) == ["Why?"])
      #expect(note.exchanges.map(\.answer) == ["Because nodes differ."])
      #expect(note.exchanges.map(\.mentor) == [mentor.id])
      #expect(done.messages.last?.body == .savedToNote(note.id))
    }
  }

  @Test func askingAgainAboutTheSamePassageAddsToTheSameHighlight() async throws {
    try await withHost(agent: Self.agent) { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))
      let passage = try passage(mentor.id)
      let highlight = try await host.run(AddNote(locator: passage.locator, excerpt: passage.excerpt, thought: "Hm"))

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Why?", passage: passage))
      _ = try #require(await settled(host, mentor.id, turns: 2))
      _ = try await host.run(SendMessage(mentor: mentor.id, text: "And then?", passage: passage))
      _ = try #require(await settled(host, mentor.id, turns: 3))

      let notes = place.store.notes(on: passage.locator.content).value
      #expect(notes.map(\.id) == [highlight.id])
      #expect(notes.first?.thought == "Hm")
      #expect(notes.first?.exchanges.map(\.question) == ["Why?", "And then?"])
    }
  }

  @Test func aStoppedAnswerIsNotSaved() async throws {
    let agent = FakeAgent { prompt in prompt.contains("new mentor") ? .reply("Ready.") : .hang }
    try await withHost(agent: agent) { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))
      let passage = try passage(mentor.id)

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Why?", passage: passage))
      _ = try await host.run(StopTurn(mentor: mentor.id))

      let done = try #require(await settled(host, mentor.id, turns: 2))
      #expect(place.store.notes(on: passage.locator.content).value.first?.exchanges.isEmpty == true)
      #expect(!done.messages.contains { if case .savedToNote = $0.body { true } else { false } })
    }
  }

  @Test func aFailedAnswerIsNotSaved() async throws {
    try await withHost { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))
      try place.store.save(
        try Mentor(id: mentor.id, name: mentor.name, avatar: mentor.avatar, color: mentor.color, provider: .grok))
      let passage = try passage(mentor.id)

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Why?", passage: passage))

      let done = try #require(await settled(host, mentor.id, turns: 2))
      #expect(done.messages.last?.body == .ended(.unstarted(.grok, .notInstalled)))
      #expect(place.store.notes(on: passage.locator.content).value.first?.exchanges.isEmpty == true)
    }
  }

  @Test func aDeletedHighlightIsNotBroughtBack() async throws {
    try await withManualHost { host, place, _, agent in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await settled(host, mentor.id))
      let passage = try passage(mentor.id)

      _ = try await host.run(SendMessage(mentor: mentor.id, text: "Why?", passage: passage))
      let note = try #require(place.store.notes(on: passage.locator.content).value.first)
      _ = try await host.run(DeleteNote(content: passage.locator.content, note: note.id))
      await agent.sessions.last?.finish()

      _ = try #require(await settled(host, mentor.id, turns: 2))
      #expect(place.store.notes(on: passage.locator.content).value.isEmpty)
    }
  }

  @Test func aPassageQuestionWhileTheMentorIsWorkingIsRefusedWithoutAHighlight() async throws {
    try await withHost(agent: FakeAgent { _ in .hang }) { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let passage = try passage(mentor.id)

      await #expect(throws: HostError.self) {
        try await host.run(SendMessage(mentor: mentor.id, text: "Why?", passage: passage))
      }
      #expect(place.store.notes(on: passage.locator.content).value.isEmpty)
      _ = try await host.run(StopTurn(mentor: mentor.id))
    }
  }
}
