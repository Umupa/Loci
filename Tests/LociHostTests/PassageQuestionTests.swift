import Foundation
import LociModel
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct PassageQuestionTests {
  private static var agent: FakeAgent {
    FakeAgent { prompt in
      prompt.contains("asks about this passage") ? .reply("Because nodes differ.") : .reply("Ready.")
    }
  }

  private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<500 {
      if condition() { return true }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return false
  }

  private func lessonLocator(_ mentor: EntityID) throws -> Locator {
    .lesson(LessonRef(mentor: mentor, lesson: Lesson.Slug("why-schedule")!), try TextQuote("Pods need a node."))
  }

  /// α2-S4: a question about a sentence becomes a note, and the answer arrives in it.
  @Test func aQuestionBecomesANoteAndItsAnswerArrives() async throws {
    try await withHost(agent: Self.agent) { host, place, world in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let locator = try lessonLocator(mentor.id)
      let pending = host.subscribe(PendingAnswers(content: locator.content))

      let note = try await host.run(
        AskAboutPassage(mentor: mentor.id, locator: locator, excerpt: "Pods need a node.", question: "Why?"))

      let streaming = await value(pending) { $0.first?.answer == "Because" }
      #expect(streaming?.first?.note == note)
      let finished = await value(pending) { $0.isEmpty }
      #expect(finished != nil)
      let saved = try #require(place.store.notes(on: locator.content).value.first)
      #expect(saved.id == note)
      #expect(saved.excerpt == "Pods need a node.")
      #expect(saved.exchanges.map(\.question) == ["Why?"])
      #expect(saved.exchanges.map(\.answer) == ["Because nodes differ."])
      #expect(saved.exchanges.map(\.mentor) == [mentor.id])
      #expect(world.agent.prompts.contains { $0.contains("> Pods need a node.") && $0.contains("Why?") })
    }
  }

  @Test func aSecondQuestionOnTheSameNoteIsAddedToIt() async throws {
    try await withHost(agent: Self.agent) { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let locator = try lessonLocator(mentor.id)
      let pending = host.subscribe(PendingAnswers(content: locator.content))
      let note = try await host.run(
        AskAboutPassage(mentor: mentor.id, locator: locator, excerpt: nil, question: "Why?"))
      _ = await value(pending) { $0.isEmpty }

      _ = try await host.run(
        AskAboutPassage(mentor: mentor.id, locator: locator, excerpt: nil, question: "And then?", note: note))

      let asked = await eventually { place.store.notes(on: locator.content).value.first?.exchanges.count == 2 }
      #expect(asked)
      let notes = place.store.notes(on: locator.content).value
      #expect(notes.count == 1)
      #expect(notes.first?.exchanges.map(\.question) == ["Why?", "And then?"])
    }
  }

  @Test func aQuestionAnsweredWhileTheMentorIsBusyStillArrives() async throws {
    let agent = FakeAgent { prompt in prompt.contains("asks about this passage") ? .reply("Yes.") : .hang }
    try await withHost(agent: agent) { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let locator = try lessonLocator(mentor.id)

      _ = try await host.run(AskAboutPassage(mentor: mentor.id, locator: locator, excerpt: nil, question: "Really?"))

      _ = await value(host.subscribe(PendingAnswers(content: locator.content))) { $0.isEmpty }
      #expect(place.store.notes(on: locator.content).value.first?.exchanges.first?.answer == "Yes.")
      _ = try await host.run(StopTurn(mentor: mentor.id))
    }
  }

  @Test func aQuestionWhoseAgentIsMissingFailsVisibly() async throws {
    try await withHost { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      try place.store.save(
        try Mentor(
          id: mentor.id, name: mentor.name, avatar: mentor.avatar, color: mentor.color, provider: .grok,
          permission: .full))
      let locator = try lessonLocator(mentor.id)

      _ = try await host.run(AskAboutPassage(mentor: mentor.id, locator: locator, excerpt: nil, question: "Why?"))

      let failed = await value(host.subscribe(PendingAnswers(content: locator.content))) { $0.first?.failure != nil }
      #expect(failed?.first?.failure == "grok is not installed on this Mac.")
    }
  }

  @Test func anEmptyQuestionIsRefused() async throws {
    try await withHost { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      await #expect(throws: HostError.self) {
        try await host.run(
          AskAboutPassage(mentor: mentor.id, locator: try lessonLocator(mentor.id), excerpt: nil, question: "  "))
      }
    }
  }
}
