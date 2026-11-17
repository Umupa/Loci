/// Says something to a mentor. The reply arrives through `MentorConversation`.
///
/// Refused while the mentor is still working on a turn. A mentor whose agent cannot start still gets
/// the message; the turn then ends at once with `.failed` saying why.
public struct SendMessage: Command {
  public static let name = "conversation.send"
  public let mentor: EntityID
  public let text: String

  public init(mentor: EntityID, text: String) {
    self.mentor = mentor
    self.text = text
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

/// Answers one of `LiveTurn.waiting`. An unknown or already answered request is ignored.
public struct AnswerPermission: Command {
  public static let name = "conversation.answer"
  public let mentor: EntityID
  public let request: String
  public let answer: PermissionAsk.Answer

  public init(mentor: EntityID, request: String, answer: PermissionAsk.Answer) {
    self.mentor = mentor
    self.request = request
    self.answer = answer
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.answerPermission(self)
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

/// Asks a mentor about a passage. Replies with the note the exchange goes into: `note` when given,
/// otherwise a new note on the passage, saved at once with the excerpt.
///
/// The answer streams through `PendingAnswers` and is added to the note when complete. Questions run
/// beside the mentor's conversation, so they are answered even while it is writing a lesson.
public struct AskAboutPassage: Command {
  public static let name = "note.ask"
  public let mentor: EntityID
  public let locator: Locator
  public let excerpt: String?
  public let question: String
  /// An existing note on the same passage to add the exchange to.
  public let note: EntityID?

  public init(mentor: EntityID, locator: Locator, excerpt: String?, question: String, note: EntityID? = nil) {
    self.mentor = mentor
    self.locator = locator
    self.excerpt = excerpt
    self.question = question
    self.note = note
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> EntityID {
    try await handler.askAboutPassage(self)
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
      case .catalog, .lesson, .item, .notes, .answers, .reading: false
      }
    }
  }
}

/// Questions about passages in one piece of content whose answers are still arriving.
public struct PendingAnswers: Subscription {
  public static let name = "answers"
  public let content: ContentRef

  public init(content: ContentRef) {
    self.content = content
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> [PendingAnswer] {
    await handler.pendingAnswers(on: content)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.answers(content)) || changes.contains(.everything)
  }
}
