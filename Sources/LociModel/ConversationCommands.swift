/// Says something to a mentor. The reply arrives through `MentorConversation`.
///
/// With a passage, the message is a question about it: the passage gets a note unless it has one, and when
/// the turn ends with a reply, the question and the reply are saved in that note.
///
/// Refused while the mentor is still working on a turn. A mentor whose agent cannot start still gets
/// the message; the turn then ends at once with `.failed` saying why.
public struct SendMessage: Command {
  public static let name = "conversation.send"
  public let mentor: EntityID
  public let text: String
  public let passage: Passage?

  public init(mentor: EntityID, text: String, passage: Passage? = nil) {
    self.mentor = mentor
    self.text = text
    self.passage = passage
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.sendMessage(self)
  }
}

/// Stops the mentor's running turn and returns once it has stopped. Does nothing when it is idle.
public struct StopTurn: Command {
  public static let name = "conversation.stop"
  public let mentor: EntityID

  public init(mentor: EntityID) {
    self.mentor = mentor
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.stopTurn(self)
  }
}

/// Asks the mentor to write a lesson its catalog lists but that has no text yet.
///
/// Refused for a lesson that is not in the catalog, one already written, or while the mentor is busy.
public struct WriteLesson: Command {
  public static let name = "lesson.write"
  public let lesson: LessonRef

  public init(lesson: LessonRef) {
    self.lesson = lesson
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.writeLesson(self)
  }
}

/// A mentor's conversation, kept current as the mentor works.
public struct MentorConversation: Subscription {
  public static let name = "conversation"
  public let mentor: EntityID

  public init(mentor: EntityID) {
    self.mentor = mentor
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> Conversation {
    try await handler.conversation(of: mentor)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .conversation(let id), .mentor(let id): id == mentor
      case .everything: true
      case .catalog, .lesson, .item, .notes, .mind, .reading, .job: false
      }
    }
  }
}

/// Words the person picked in something they are reading.
public struct Passage: Hashable, Codable, Sendable {
  public let locator: Locator
  public let excerpt: String

  public init(locator: Locator, excerpt: String) {
    self.locator = locator
    self.excerpt = excerpt
  }
}
