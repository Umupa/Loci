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

  /// The stored messages and the running turn come from the run; the main conversation adds what happened
  /// in the library, in the order it happened.
  public func conversation(_ ref: ConversationRef) async throws(HostError) -> Conversation {
    let snapshot = await (try loci.run(of: ref)).snapshot
    var entries = snapshot.messages.map(Conversation.Entry.message)
    if ref == .main {
      entries = Self.merging(entries, try await events())
    }
    return Conversation(ref: ref, entries: entries, turn: snapshot.turn, context: snapshot.context)
  }

  /// The events the main conversation shows; an event about an item that is gone is left out.
  private func events() async throws(HostError) -> [WorldEvent] {
    let events = try attempt { try database.events() }.filter { logged in
      if case .highlighted = logged.event { return false }
      return true
    }
    let items = store.items(withIDs: Set(events.map(\.event.item)))
    var shown: [WorldEvent] = []
    for logged in events {
      guard let item = items[logged.event.item] else { continue }
      switch logged.event {
      case .finishedReading:
        shown.append(WorldEvent(id: logged.id, at: logged.at, kind: .finishedReading(item)))
      case .saved:
        let job = await library.queue.job(of: item.id)
        shown.append(WorldEvent(id: logged.id, at: logged.at, kind: .saved(item, job: job)))
      case .highlighted:
        continue
      }
    }
    return shown
  }

  /// Both lists are in time order; an event goes after the messages of the same moment.
  static func merging(_ messages: [Conversation.Entry], _ events: [WorldEvent]) -> [Conversation.Entry] {
    var merged: [Conversation.Entry] = []
    var rest = events[...]
    for message in messages {
      while let event = rest.first, event.at < message.at {
        merged.append(.event(event))
        rest = rest.dropFirst()
      }
      merged.append(message)
    }
    return merged + rest.map(Conversation.Entry.event)
  }

  /// Tells of an item that went into the library. What the person saved is logged for the main
  /// conversation and for Loci; what Loci saved shows in the turn it was saved in, and Loci knows it already.
  func saved(_ item: EntityID, by saver: Saver) async {
    if case .loci = saver { await library.queue.joinSaving(item) }
    switch saver {
    case .person: await happened(.saved(item))
    case .loci(let conversation?): await loci.saved(item, in: conversation)
    case .loci(nil): break
    }
  }

  /// Logs something that happened in the library and tells the main conversation.
  func happened(_ event: LibraryEvent) async {
    try? database.log(LoggedEvent(id: environment.newID(), at: environment.now(), event: event))
    await follow([.events])
  }
}
