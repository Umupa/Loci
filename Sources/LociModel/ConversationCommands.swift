/// Says something to Loci in a conversation. The reply arrives through `OneConversation`.
///
/// With a passage, the message is a question about it: the passage gets a note unless it has one, and
/// when the turn ends with a reply, the question and the reply are saved in that note. A passage is
/// taken only in the conversation of that item or course.
///
/// Refused while the conversation has a turn running. A runtime that cannot start still takes the
/// message; the turn then ends at once with `.failed` saying why.
public struct SendMessage: RemoteCommand {
  public static let name = "conversation.send"
  public let conversation: ConversationRef
  public let text: String
  public let passage: Passage?
  public let lesson: Lesson.ID?

  public init(to conversation: ConversationRef, text: String, passage: Passage? = nil, lesson: Lesson.ID? = nil) {
    self.conversation = conversation
    self.text = text
    self.passage = passage
    self.lesson = lesson
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.sendMessage(self)
  }
}

/// Stops the conversation's running turn and returns once it has stopped. Does nothing when none runs.
public struct StopTurn: RemoteCommand {
  public static let name = "conversation.stop"
  public let conversation: ConversationRef

  public init(in conversation: ConversationRef) {
    self.conversation = conversation
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.stopTurn(self)
  }
}

/// `/new`: the conversation's next message opens a fresh session that remembers nothing said before.
/// Every message stays, with a `.startedOver` line. Does nothing on an empty conversation or right after
/// another start over; refused while a turn runs.
public struct StartOver: RemoteCommand {
  public static let name = "conversation.startOver"
  public let conversation: ConversationRef

  public init(in conversation: ConversationRef) {
    self.conversation = conversation
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.startOver(self)
  }
}

/// One conversation, kept current as Loci answers. An item's conversation is unavailable once it is deleted.
public struct OneConversation: Subscription {
  public static let name = "conversation"
  public let conversation: ConversationRef

  public init(_ conversation: ConversationRef) {
    self.conversation = conversation
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> Conversation {
    try await handler.conversation(conversation)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .conversation(let changed), .turnEnded(let changed): changed == conversation
      case .everything: true
      case .item(let item): conversation == .item(item)
      case .course(let id): conversation == .course(id)
      case .courseActivity, .notes, .reading, .job, .media, .review, .loci, .runtime, .timers, .connectors: false
      }
    }
  }
}

/// Words the person picked in something they are reading, and the pictures among them.
public struct Passage: Hashable, Codable, Sendable {
  public let locator: Locator
  /// Empty when only a picture was picked.
  public let excerpt: String
  /// By their address in the item's text. A Mac before pictures ignores them.
  public let pictures: [String]

  public init(locator: Locator, excerpt: String, pictures: [String] = []) {
    self.locator = locator
    self.excerpt = excerpt
    self.pictures = pictures
  }

  private enum CodingKeys: String, CodingKey {
    case locator, excerpt, pictures
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    locator = try container.decode(Locator.self, forKey: .locator)
    excerpt = try container.decode(String.self, forKey: .excerpt)
    pictures = try container.decodeIfPresent([String].self, forKey: .pictures) ?? []
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(locator, forKey: .locator)
    try container.encode(excerpt, forKey: .excerpt)
    if !pictures.isEmpty { try container.encode(pictures, forKey: .pictures) }
  }
}
