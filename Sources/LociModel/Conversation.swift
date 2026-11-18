/// Everything said between the person and one mentor, oldest first, and the turn running now.
///
/// Messages are only ever added: a turn's messages move from `turn` to `messages` when it ends, and a
/// stored message never changes.
public struct Conversation: Hashable, Codable, Sendable {
  public let mentor: EntityID
  public let messages: [Message]
  /// `nil` while the mentor is idle.
  public let turn: LiveTurn?
  /// How full the agent's context window was when it last said; `nil` until it says.
  public let context: ContextUsage?

  public init(mentor: EntityID, messages: [Message], turn: LiveTurn?, context: ContextUsage? = nil) {
    self.mentor = mentor
    self.messages = messages
    self.turn = turn
    self.context = context
  }
}

/// The turn the mentor is working on.
public struct LiveTurn: Hashable, Codable, Sendable {
  public let startedAt: Timestamp
  /// What the turn has produced so far, starting with its prompt. The last reply, thinking or tool may
  /// still grow.
  public let messages: [Message]

  public init(startedAt: Timestamp, messages: [Message]) {
    self.startedAt = startedAt
    self.messages = messages
  }

  /// The tool the mentor used last: what it is doing, or did most recently.
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
    /// What the mentor was asked, by the person or by Loci.
    case prompt(Prompt)
    /// Part of the mentor's reply. A reply interrupted by tool calls is several messages.
    case reply(String)
    case thinking(String)
    case tool(ToolActivity)
    /// The question and its answer were saved in this note on the passage the question was about.
    case savedToNote(EntityID)
    /// Something the agent reported that is not part of the reply: a retry, compaction, a warning.
    case notice(String)
    /// How a turn ended, when it did not simply finish.
    case ended(TurnEnding)
    /// The person started over: the agent remembers nothing said before this, which still shows.
    case startedOver
  }
}

public struct Prompt: Hashable, Codable, Sendable {
  public let text: String
  public let purpose: Purpose
  /// The passage the person asked about, when they asked about one.
  public let passage: QuotedPassage?

  public init(text: String, purpose: Purpose, passage: QuotedPassage? = nil) {
    self.text = text
    self.purpose = purpose
    self.passage = passage
  }

  /// Why the prompt was sent. Only `.chat` was typed by the person; the others Loci wrote for them.
  public enum Purpose: Hashable, Codable, Sendable {
    case chat
    /// A new mentor's first work: the catalog, then the first lesson.
    case begin
    case writeLesson(Lesson.Slug)
  }
}

public enum TurnEnding: Hashable, Codable, Sendable {
  /// Stopped on the person's request.
  case interrupted
  /// The agent could not go on. Carries its own words.
  case failed(String)
  /// The mentor's agent did not start.
  case unstarted(Mentor.Provider, AgentStartFailure)
}

/// Why an agent's program did not start.
public enum AgentStartFailure: Hashable, Codable, Sendable {
  /// No program for it was found on this Mac.
  case notInstalled
  /// The program is there but would not start: this Mac did not let Loci run it, or it is broken.
  case wouldNotStart
}

/// A tool the mentor ran during a turn.
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
  public let note: EntityID

  public init(locator: Locator, excerpt: String, note: EntityID) {
    self.locator = locator
    self.excerpt = excerpt
    self.note = note
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
