/// The conversation on one item: what every mentor who read along was asked and answered there, oldest
/// first, each message with the mentor it was between.
public struct ItemConversation: Hashable, Codable, Sendable {
  public let item: EntityID
  /// The mentor reading along now; `nil` until one is chosen, or when there are no mentors.
  public let companion: EntityID?
  public let messages: [AttributedMessage]
  /// `nil` while no mentor is answering on the item.
  public let turn: CompanionTurn?
  /// How full the companion's context window on this item was when its agent last said.
  public let context: ContextUsage?

  public init(
    item: EntityID, companion: EntityID?, messages: [AttributedMessage], turn: CompanionTurn?,
    context: ContextUsage? = nil
  ) {
    self.item = item
    self.companion = companion
    self.messages = messages
    self.turn = turn
    self.context = context
  }
}

/// A message in an item's conversation, with the mentor who answered it or was asked it.
public struct AttributedMessage: Hashable, Codable, Sendable, Identifiable {
  public let mentor: EntityID
  public let message: Message

  public init(mentor: EntityID, message: Message) {
    self.mentor = mentor
    self.message = message
  }

  public var id: EntityID { message.id }
}

/// The turn running on an item, and the mentor answering in it.
public struct CompanionTurn: Hashable, Codable, Sendable {
  public let mentor: EntityID
  public let turn: LiveTurn

  public init(mentor: EntityID, turn: LiveTurn) {
    self.mentor = mentor
    self.turn = turn
  }
}
