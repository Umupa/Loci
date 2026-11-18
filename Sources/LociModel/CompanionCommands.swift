/// Asks a mentor about an item, and makes it the item's companion. The reply arrives through
/// `CompanionConversation`.
///
/// Each mentor answers on an item in a session of its own, with its own soul and memory, separate from its
/// conversation about its course. With a passage, the message is a question about it: the passage gets a
/// note unless it has one, and when the turn ends with a reply, the question and the reply are saved in
/// that note.
///
/// Refused while any mentor is still answering on the item. A mentor whose agent cannot start still gets
/// the message; the turn then ends at once with `.failed` saying why.
public struct AskCompanion: Command {
  public static let name = "companion.send"
  public let item: EntityID
  public let mentor: EntityID
  public let text: String
  public let passage: Passage?

  public init(item: EntityID, mentor: EntityID, text: String, passage: Passage? = nil) {
    self.item = item
    self.mentor = mentor
    self.text = text
    self.passage = passage
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.askCompanion(self)
  }
}

/// Stops the turn running on the item and returns once it has stopped. Does nothing when none is.
public struct StopCompanion: Command {
  public static let name = "companion.stop"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.stopCompanion(self)
  }
}

/// Makes a mentor the item's companion without asking it anything. Remembered for the item, and offered
/// on items where no companion was chosen yet.
public struct ChooseCompanion: Command {
  public static let name = "companion.choose"
  public let item: EntityID
  public let mentor: EntityID

  public init(item: EntityID, mentor: EntityID) {
    self.item = item
    self.mentor = mentor
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> ItemConversation {
    try await handler.chooseCompanion(self)
  }
}

/// An item's conversation, kept current as its companions answer.
public struct CompanionConversation: Subscription {
  public static let name = "companion.conversation"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> ItemConversation {
    try await handler.itemConversation(on: item)
  }

  /// A mentor that is deleted or renamed may be the companion.
  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .itemConversation(let id), .item(let id): id == item
      case .mentor, .everything: true
      case .catalog, .lesson, .notes, .conversation, .mind, .reading, .job, .media: false
      }
    }
  }
}
