import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func sendMessage(_ command: SendMessage) async throws(HostError) -> Done {
    let text = command.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw .invalidRequest("the message is empty") }
    try await mentors.run(of: command.mentor).send(Prompt(text: text, purpose: .chat))
    return Done()
  }

  public func stopTurn(_ command: StopTurn) async throws(HostError) -> Done {
    await (try mentors.run(of: command.mentor)).stop()
    return Done()
  }

  public func answerPermission(_ command: AnswerPermission) async throws(HostError) -> Done {
    await (try mentors.run(of: command.mentor)).answer(command.request, with: command.answer)
    return Done()
  }

  public func writeLesson(_ command: WriteLesson) async throws(HostError) -> Done {
    let ref = command.lesson
    let page = try await mentorPage(ref.mentor)
    guard let lesson = page.catalog?.chapters.flatMap(\.lessons).first(where: { $0.slug == ref.lesson }) else {
      throw .invalidRequest("\(ref.lesson) is not in the catalog")
    }
    guard !page.writtenLessons.contains(ref.lesson) else { throw .invalidRequest("\(ref.lesson) is already written") }
    try await mentors.run(of: ref.mentor).send(Soul.write(lesson))
    return Done()
  }

  public func askAboutPassage(_ command: AskAboutPassage) async throws(HostError) -> EntityID {
    let question = command.question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty else { throw .invalidRequest("the question is empty") }
    let mentor = try attempt { try store.mentor(command.mentor) }
    let content = command.locator.content
    let note: EntityID
    if let existing = command.note {
      guard store.notes(on: content).value.contains(where: { $0.id == existing }) else {
        throw .notFound(existing.description)
      }
      note = existing
    } else {
      let made = try attempt {
        try Note(
          id: environment.newID(), locator: command.locator, excerpt: command.excerpt, savedAt: environment.now())
      }
      try attempt { try store.append(.saved(made), on: content) }
      await follow([.notes(content)])
      note = made.id
    }
    await mentors.questions.ask(
      question, of: mentor, about: command.locator, excerpt: command.excerpt, note: note)
    return note
  }

  public func conversation(of mentor: EntityID) async throws(HostError) -> Conversation {
    await (try mentors.run(of: mentor)).snapshot()
  }

  public func pendingAnswers(on content: ContentRef) async -> [PendingAnswer] {
    await mentors.questions.pending(on: content)
  }

  /// A new mentor's first turn: the catalog, then the first lesson.
  func begin(_ mentor: Mentor) async throws(HostError) {
    try await mentors.run(of: mentor.id).send(Soul.begin(mentor))
  }
}
