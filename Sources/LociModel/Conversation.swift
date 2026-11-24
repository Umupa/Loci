/// Which conversation: the one main conversation, or the one on an item or course.
public enum ConversationRef: Hashable, Codable, Sendable {
  case main
  case item(EntityID)
  case course(EntityID)
}

/// Everything said in one conversation, oldest first, and the turn running now.
///
/// It only ever grows: a turn's messages move from `turn` to `entries` when it ends. The agent sessions
/// underneath change without a trace, except `/new`, which leaves a `.startedOver` line.
public struct Conversation: Hashable, Codable, Sendable {
  public let ref: ConversationRef
  public let entries: [Entry]
  /// `nil` while Loci is not answering here.
  public let turn: LiveTurn?
  /// How full the current session's context window was when the agent last said; `nil` until it says.
  public let context: ContextUsage?

  public init(ref: ConversationRef, entries: [Entry], turn: LiveTurn?, context: ContextUsage? = nil) {
    self.ref = ref
    self.entries = entries
    self.turn = turn
    self.context = context
  }

  public enum Entry: Hashable, Codable, Sendable, Identifiable {
    case message(Message)
    /// Only received from older hosts.
    case event(WorldEvent)

    public var id: EntityID {
      switch self {
      case .message(let message): message.id
      case .event(let event): event.id
      }
    }

    public var at: Timestamp {
      switch self {
      case .message(let message): message.at
      case .event(let event): event.at
      }
    }
  }
}

/// The turn Loci is working on.
public struct LiveTurn: Hashable, Codable, Sendable {
  public let startedAt: Timestamp
  /// What the turn has produced so far, starting with its prompt. The last reply, thinking or tool may
  /// still grow.
  public let messages: [Message]

  public init(startedAt: Timestamp, messages: [Message]) {
    self.startedAt = startedAt
    self.messages = messages
  }

  /// The tool Loci used last: what it is doing, or did most recently.
  public var latestTool: ToolActivity? {
    messages.reversed().lazy.compactMap { message in
      guard case .tool(let tool) = message.body else { return nil }
      return tool
    }.first
  }
}

public struct Message: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let at: Timestamp
  public let body: Body

  public init(id: EntityID, at: Timestamp, body: Body) {
    self.id = id
    self.at = at
    self.body = body
  }

  public enum Body: Hashable, Codable, Sendable {
    /// What Loci was asked, by the person or by the app.
    case prompt(Prompt)
    /// Part of Loci's reply. A reply interrupted by tool calls is several messages.
    case reply(String)
    case thinking(String)
    case tool(ToolActivity)
    /// The question and its answer were saved in this note on the passage the question was about.
    case savedToNote(EntityID)
    /// Loci put this item into the library during the turn, with the `loci` command.
    case savedItem(EntityID)
    /// Something the agent reported that is not part of the reply: a retry, compaction, a warning.
    case notice(String)
    /// How a turn ended, when it did not simply finish.
    case ended(TurnEnding)
    /// The person started over: the agent remembers nothing said before this, which still shows.
    case startedOver
  }
}

extension Message {
  /// Whether the person wrote it, rather than the app.
  public var isTyped: Bool {
    if case .prompt(let prompt) = body { prompt.purpose == .chat } else { false }
  }
}

public struct Prompt: Hashable, Codable, Sendable {
  public let text: String
  public let purpose: Purpose
  /// The passage the person asked about, when they asked about one.
  public let passage: QuotedPassage?
  /// The title of the lesson when the person asked for it to be written.
  public let lessonTitle: String?

  public init(text: String, purpose: Purpose, passage: QuotedPassage? = nil, lessonTitle: String? = nil) {
    self.text = text
    self.purpose = purpose
    self.passage = passage
    self.lessonTitle = lessonTitle
  }

  /// Why the prompt was sent.
  public enum Purpose: Hashable, Codable, Sendable {
    /// Typed by the person.
    case chat
    /// The app asking Loci to look back on a day. It belongs to no conversation.
    case review(Day)
    /// The app asking Loci to refresh the panel by this name. It belongs to no conversation.
    case panel(String)
    /// The app asking Loci to do a run in the background. It belongs to no conversation.
    case run(Run.ID)
    case course(CourseEvent)
  }
}

public enum TurnEnding: Hashable, Codable, Sendable {
  /// Stopped on the person's request.
  case interrupted
  /// The agent could not go on. Carries its own words.
  case failed(String)
  /// Loci's agent program did not start.
  case unstarted(Provider, AgentStartFailure)
}

/// Why an agent's program did not start.
public enum AgentStartFailure: Hashable, Codable, Sendable {
  /// No program for it was found on this Mac.
  case notInstalled
  /// The program is there but would not start: this Mac did not let Loci run it, or it is broken.
  case wouldNotStart
}

/// A tool Loci ran during a turn.
public struct ToolActivity: Hashable, Codable, Sendable {
  /// The provider's identifier for the call.
  public let id: String
  /// The provider's own name for the tool.
  public let name: String
  public let kind: Kind
  /// What the tool works on, when it can be told: the command, the path or the query.
  public let subject: String?
  /// What the tool has printed so far.
  public let output: String
  public let state: State

  public init(id: String, name: String, kind: Kind, subject: String?, output: String, state: State) {
    self.id = id
    self.name = name
    self.kind = kind
    self.subject = subject
    self.output = output
    self.state = state
  }

  public enum Kind: String, Hashable, Codable, Sendable {
    /// `edit` changes a file that was there, `create` writes one that was not, `delete` removes one.
    case read, edit, create, delete, execute, search, other
  }

  public enum State: String, Hashable, Codable, Sendable {
    /// Announced or running.
    case running
    case succeeded
    case failed
  }
}

/// A passage quoted in a question, and the note the answer goes into.
public struct QuotedPassage: Hashable, Codable, Sendable {
  public let locator: Locator
  public let excerpt: String
  /// By their address in the item's text.
  public let pictures: [String]
  public let note: EntityID

  public init(locator: Locator, excerpt: String, pictures: [String] = [], note: EntityID) {
    self.locator = locator
    self.excerpt = excerpt
    self.pictures = pictures
    self.note = note
  }

  private enum CodingKeys: String, CodingKey {
    case locator, excerpt, pictures, note
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    locator = try container.decode(Locator.self, forKey: .locator)
    excerpt = try container.decode(String.self, forKey: .excerpt)
    pictures = try container.decodeIfPresent([String].self, forKey: .pictures) ?? []
    note = try container.decode(EntityID.self, forKey: .note)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(locator, forKey: .locator)
    try container.encode(excerpt, forKey: .excerpt)
    if !pictures.isEmpty { try container.encode(pictures, forKey: .pictures) }
    try container.encode(note, forKey: .note)
  }
}

/// How full an agent's context window is, in tokens.
public struct ContextUsage: Hashable, Codable, Sendable {
  public let used: Int?
  public let window: Int?

  public init(used: Int?, window: Int?) {
    self.used = used
    self.window = window
  }
}
