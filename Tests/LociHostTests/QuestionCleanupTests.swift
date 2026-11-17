import LociModel
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct QuestionCleanupTests {
  private func waitUntil(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<500 {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return false
  }

  /// A deleted mentor leaves no questions behind: the one being answered and the queued one are gone, not
  /// failed, the queued one is never sent, nothing is saved, and the side session is closed.
  @Test func deletingAMentorDropsItsAnsweringAndQueuedQuestions() async throws {
    try await withManualHost { host, place, world, agent in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(
        await value(host.subscribe(MentorConversation(mentor: mentor.id))) { $0.turn == nil && !$0.messages.isEmpty })
      let locator = Locator.item(world.nextID(), .quote(try TextQuote("a passage")))
      let note = try await host.run(
        AskAboutPassage(mentor: mentor.id, locator: locator, excerpt: nil, question: "First?"))
      _ = try #require(
        await value(host.subscribe(PendingAnswers(content: locator.content))) { $0.first?.answer == "Waiting" })
      let session = try #require(await agent.sessions.last)
      _ = try await host.run(
        AskAboutPassage(mentor: mentor.id, locator: locator, excerpt: nil, question: "Queued?", note: note))

      _ = try await host.run(DeleteMentor(mentor: mentor.id, notes: .keep))

      #expect(await host.pendingAnswers(on: locator.content).isEmpty)
      #expect(await session.closed)
      #expect(await session.prompts.count == 1)
      #expect(place.store.notes(on: locator.content).value.first?.exchanges.isEmpty == true)
    }
  }

  /// A side session that finishes opening after its mentor was deleted is closed and never asked anything.
  @Test func aSessionStillOpeningWhenTheMentorIsDeletedIsClosed() async throws {
    try await withManualHost(agent: ManualAgent(opensFreely: 1)) { host, _, world, agent in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = try #require(
        await value(host.subscribe(MentorConversation(mentor: mentor.id))) { $0.turn == nil && !$0.messages.isEmpty })
      let locator = Locator.item(world.nextID(), .quote(try TextQuote("a passage")))
      _ = try await host.run(AskAboutPassage(mentor: mentor.id, locator: locator, excerpt: nil, question: "Why?"))
      #expect(await waitUntil { await agent.waitingToOpen == 1 })

      let deleting = Task { try await host.run(DeleteMentor(mentor: mentor.id, notes: .keep)) }
      #expect(await waitUntil { await host.pendingAnswers(on: locator.content).isEmpty })
      await agent.letOpen()
      _ = try await deleting.value

      let late = try #require(await agent.sessions.last)
      #expect(await agent.sessions.count == 2)
      #expect(await late.closed)
      #expect(await late.prompts.isEmpty)
      #expect(await host.pendingAnswers(on: locator.content).isEmpty)
    }
  }
}
