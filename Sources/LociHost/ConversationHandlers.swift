import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func sendMessage(_ command: SendMessage) async throws(HostError) -> Done {
    let text = command.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw .invalidRequest("the message is empty") }
    let run = try await mentors.run(of: command.mentor)
    guard let passage = command.passage else {
      try await run.send(Prompt(text: text, purpose: .chat))
      return Done()
    }
    guard await run.isIdle else { throw .invalidRequest(MentorRun.busy) }
    let quoted = QuotedPassage(
      locator: passage.locator, excerpt: passage.excerpt, note: try await note(on: passage).id)
    try await run.send(Prompt(text: text, purpose: .chat, passage: quoted), saying: Soul.ask(text, about: passage))
    return Done()
  }

  /// The note on exactly this passage, made now when there is none.
  func note(on passage: Passage) async throws(HostError) -> Note {
    let notes = store.notes(on: passage.locator.content).value
    if let existing = notes.first(where: { $0.locator == passage.locator }) { return existing }
    return try await addNote(AddNote(locator: passage.locator, excerpt: passage.excerpt))
  }

  public func stopTurn(_ command: StopTurn) async throws(HostError) -> Done {
    await (try mentors.run(of: command.mentor)).stop()
    return Done()
  }

  public func writeLesson(_ command: WriteLesson) async throws(HostError) -> Done {
    let ref = command.lesson
    let page = try await mentorPage(ref.mentor)
    guard let lesson = page.catalog?.chapters.flatMap(\.lessons).first(where: { $0.slug == ref.lesson }) else {
      throw .invalidRequest("\(ref.lesson) is not in the catalog")
    }
    guard !page.writtenLessons.contains(ref.lesson) else { throw .invalidRequest("\(ref.lesson) is already written") }
    try await mentors.run(of: ref.mentor).send(Soul.write(lesson, in: try await lessonLanguage()))
    return Done()
  }

  public func conversation(of mentor: EntityID) async throws(HostError) -> Conversation {
    await (try mentors.run(of: mentor)).snapshot()
  }

  /// A new mentor's first turn: the catalog, then the first lesson.
  func begin(_ mentor: Mentor) async throws(HostError) {
    try await mentors.run(of: mentor.id).send(Soul.begin(mentor, in: try await lessonLanguage()))
  }
}
