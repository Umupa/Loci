import LociAgents
import LociModel
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct PassageFailureTests {
  private func readyMentor(_ host: LocalHost) async throws -> Mentor {
    let mentor = try await host.run(CreateMentor(request: "Scheduling"))
    _ = try #require(
      await value(host.subscribe(MentorConversation(mentor: mentor.id))) { $0.turn == nil && !$0.messages.isEmpty })
    return mentor
  }

  private func locator(_ mentor: EntityID) throws -> Locator {
    .lesson(LessonRef(mentor: mentor, lesson: Lesson.Slug("intro")!), try TextQuote("Original sentence"))
  }

  private func ask(_ host: LocalHost, _ mentor: EntityID, _ locator: Locator, note: EntityID? = nil) async throws
    -> EntityID
  {
    try await host.run(
      AskAboutPassage(mentor: mentor, locator: locator, excerpt: "Original sentence", question: "Why?", note: note))
  }

  private func started(_ host: LocalHost, _ content: ContentRef, question: String = "Why?") async throws {
    let pending = await value(host.subscribe(PendingAnswers(content: content))) {
      $0.contains { $0.question == question && $0.answer == "Waiting" }
    }
    _ = try #require(pending)
  }

  @Test(arguments: ["Why?", "Why again?"])
  func simultaneousQuestionsOnOneNoteKeepSeparatePendingAnswers(_ secondQuestion: String) async throws {
    try await withManualHost { host, place, world, agent in
      let mentor = try await readyMentor(host)
      let locator = try locator(mentor.id)
      let note = try await ask(host, mentor.id, locator)
      try await started(host, locator.content)
      let session = try #require(await agent.sessions.last)
      _ = try await host.run(
        AskAboutPassage(mentor: mentor.id, locator: locator, excerpt: nil, question: secondQuestion, note: note))
      #expect(await host.pendingAnswers(on: locator.content).count == 2)

      await session.finish()
      let second = await value(host.subscribe(PendingAnswers(content: locator.content))) {
        $0.count == 1 && $0[0].question == secondQuestion && $0[0].answer == "Waiting"
      }
      _ = try #require(second)
      let pending = await host.pendingAnswers(on: locator.content)
      #expect(pending.map(\.question) == [secondQuestion])
      #expect(pending.map(\.answer) == ["Waiting"])
      await session.finish()
      let done = await value(host.subscribe(PendingAnswers(content: locator.content))) { $0.isEmpty }
      #expect(done != nil)
      #expect(
        place.store.notes(on: locator.content).value.first?.exchanges.map(\.question) == ["Why?", secondQuestion])
    }
  }

  @Test func aFailedAnswerKeepsItsPartialTextWithoutSavingAnExchange() async throws {
    try await withManualHost { host, place, _, agent in
      let mentor = try await readyMentor(host)
      let locator = try locator(mentor.id)
      _ = try await ask(host, mentor.id, locator)
      try await started(host, locator.content)
      let session = try #require(await agent.sessions.last)
      await session.finish(.failed(.provider("quota")))

      let failed = await value(host.subscribe(PendingAnswers(content: locator.content))) {
        $0.first?.failure == "quota"
      }
      #expect(failed?.first?.answer == "Waiting")
      #expect(await session.closed)
      #expect(place.store.notes(on: locator.content).value.first?.exchanges.isEmpty == true)
    }
  }

  @Test func deletingANoteWhileAnAnswerStreamsDoesNotBringItBack() async throws {
    try await withManualHost { host, place, _, agent in
      let mentor = try await readyMentor(host)
      let locator = try locator(mentor.id)
      let note = try await ask(host, mentor.id, locator)
      try await started(host, locator.content)
      _ = try await host.run(DeleteNote(content: locator.content, note: note))
      await agent.sessions.last?.finish()

      let failed = await value(host.subscribe(PendingAnswers(content: locator.content))) { $0.first?.failure != nil }
      #expect(failed != nil)
      #expect(place.store.notes(on: locator.content).value.isEmpty)
    }
  }

  @Test func anExistingNoteFromOtherContentIsRefusedBeforeAskingTheAgent() async throws {
    try await withHost { host, _, world in
      let mentor = try await readyMentor(host)
      let locator = try locator(mentor.id)
      let note = try await host.run(AddNote(locator: locator, excerpt: nil))
      let elsewhere = Locator.item(world.nextID(), .quote(try TextQuote("elsewhere")))

      await #expect(throws: HostError.notFound(note.id.description)) {
        try await ask(host, mentor.id, elsewhere, note: note.id)
      }
      #expect(await host.pendingAnswers(on: elsewhere.content).isEmpty)
      #expect(!world.agent.prompts.contains { $0.contains("asks about this passage") })
    }
  }

  @Test func aPermissionRequestInAPassageAnswerIsDismissed() async throws {
    try await withManualHost { host, _, _, agent in
      let mentor = try await readyMentor(host)
      let locator = try locator(mentor.id)
      _ = try await ask(host, mentor.id, locator)
      try await started(host, locator.content)
      let session = try #require(await agent.sessions.last)
      await session.emit(.permission(PermissionRequest(id: .init("ask"), title: "bash", options: [])))
      await session.finish()
      _ = await value(host.subscribe(PendingAnswers(content: locator.content))) { $0.isEmpty }
      #expect(await session.answers == [.dismissed])
    }
  }
}
