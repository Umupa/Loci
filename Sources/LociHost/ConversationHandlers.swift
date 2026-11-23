import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func sendMessage(_ command: SendMessage) async throws(HostError) -> Done {
    let text = command.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw .invalidRequest("the message is empty") }
    if case .course(let id) = command.conversation {
      return try await sendCourseMessage(command, text: text, course: id)
    }
    guard command.lesson == nil else { throw .invalidRequest("a lesson belongs to a course conversation") }
    let run = try await loci.run(of: command.conversation)
    guard let passage = command.passage else {
      try await run.send(Prompt(text: text, purpose: .chat), saying: text)
      return Done()
    }
    guard case .item(let item) = command.conversation, passage.locator.content == .item(item) else {
      throw .invalidRequest("the passage is not in this item")
    }
    guard await run.isIdle else { throw .invalidRequest(AgentRun.busy) }
    let quoted = QuotedPassage(
      locator: passage.locator, excerpt: passage.excerpt, note: try await note(on: passage).id)
    try await run.send(
      Prompt(text: text, purpose: .chat, passage: quoted), saying: Prompts.ask(text, about: passage))
    return Done()
  }

  /// The note on exactly this passage, made now when there is none.
  func note(on passage: Passage) async throws(HostError) -> Note {
    let notes = store.notes(on: passage.locator.content).value
    if let existing = notes.first(where: { $0.locator == passage.locator }) { return existing }
    return try await addNote(AddNote(locator: passage.locator, excerpt: passage.excerpt))
  }

  private func sendCourseMessage(_ command: SendMessage, text: String, course: EntityID)
    async throws(HostError) -> Done
  {
    if let passage = command.passage {
      guard case .lesson(let owner, let lesson) = passage.locator.content, owner == course,
        command.lesson == nil || command.lesson == lesson
      else { throw .invalidRequest("the passage is not in this course lesson") }
      guard try await courses.page(course).activity == .idle else { throw .invalidRequest(AgentRun.busy) }
      let quoted = QuotedPassage(
        locator: passage.locator, excerpt: passage.excerpt, note: try await note(on: passage).id)
      try await courses.say(
        Prompt(text: text, purpose: .chat, passage: quoted), text: Prompts.ask(text, about: passage),
        about: lesson, in: course)
    } else {
      try await courses.say(Prompt(text: text, purpose: .chat), text: text, about: command.lesson, in: course)
    }
    return Done()
  }

  public func stopTurn(_ command: StopTurn) async throws(HostError) -> Done {
    if case .course(let course) = command.conversation {
      try await courses.pause(course)
    } else {
      await loci.existingRun(of: command.conversation)?.stop()
    }
    return Done()
  }

  public func startOver(_ command: StartOver) async throws(HostError) -> Done {
    try await loci.run(of: command.conversation).startOver()
    return Done()
  }

  public func conversation(_ ref: ConversationRef) async throws(HostError) -> Conversation {
    let snapshot = await (try loci.run(of: ref)).snapshot
    return Conversation(
      ref: ref, entries: snapshot.messages.map(Conversation.Entry.message), turn: snapshot.turn,
      context: snapshot.context)
  }

  /// What the person saved becomes context; what Loci saved shows in the turn that saved it.
  func saved(_ item: EntityID, by saver: Saver) async {
    if case .loci = saver { await library.queue.joinSaving(item) }
    switch saver {
    case .person: happened(.saved(item))
    case .loci(let conversation?): await loci.saved(item, in: conversation)
    case .loci(nil): break
    }
  }

  /// Records a library event for the companion's turn context.
  func happened(_ event: LibraryEvent) {
    try? database.log(LoggedEvent(id: environment.newID(), at: environment.now(), event: event))
  }
}
