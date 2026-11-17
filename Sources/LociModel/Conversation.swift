/// Everything said between the person and one mentor, oldest first, and the turn running now.
///
/// Messages are only ever added: a turn's messages move from `turn` to `messages` when it ends, and a
/// stored message never changes.
public struct Conversation: Hashable, Codable, Sendable {
  public let mentor: EntityID
  public let messages: [Message]
  /// `nil` while the mentor is idle.
  public let turn: LiveTurn?

  public init(mentor: EntityID, messages: [Message], turn: LiveTurn?) {
    self.mentor = mentor
    self.messages = messages
    self.turn = turn
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

  /// Permission requests the turn is waiting on, in the order they were asked.
  public var waiting: [PermissionAsk] {
    messages.compactMap { message in
      guard case .permission(let ask) = message.body, ask.answer == nil else { return nil }
      return ask
    }
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
    case permission(PermissionAsk)
    /// Something the agent reported that is not part of the reply: a retry, compaction, a warning.
    case notice(String)
    /// How a turn ended, when it did not simply finish.
    case ended(TurnEnding)
  }
}

public struct Prompt: Hashable, Codable, Sendable {
  public let text: String
  public let purpose: Purpose

  public init(text: String, purpose: Purpose) {
    self.text = text
    self.purpose = purpose
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
  /// The agent could not go on. Carries its own words, or why it would not start.
  case failed(String)
}

/// A tool the mentor ran during a turn.
public struct ToolActivity: Hashable, Codable, Sendable {
  /// The provider's identifier for the call; permission requests refer to it.
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
    case read, edit, execute, search, other
  }

  public enum State: String, Hashable, Codable, Sendable {
    /// Announced or running.
    case running
    case succeeded
    case failed
  }
}

/// The mentor asks before going on. The turn waits until it is answered with `AnswerPermission`.
public struct PermissionAsk: Hashable, Codable, Sendable {
  public let id: String
  public let title: String
  /// The tool call waiting on this answer, when the provider says which one.
  public let tool: String?
  public let options: [Option]
  /// `nil` while waiting.
  public let answer: Answer?

  public init(id: String, title: String, tool: String?, options: [Option], answer: Answer?) {
    self.id = id
    self.title = title
    self.tool = tool
    self.options = options
    self.answer = answer
  }

  public struct Option: Hashable, Codable, Sendable {
    public let id: String
    public let role: Role
    /// The provider's own wording, when it has one.
    public let label: String?

    public init(id: String, role: Role, label: String?) {
      self.id = id
      self.role = role
      self.label = label
    }
  }

  public enum Role: String, Hashable, Codable, Sendable {
    case allow, allowAlways, deny, denyAlways
    /// One of several answers with no allow or deny meaning.
    case choice
  }

  public enum Answer: Hashable, Codable, Sendable {
    /// The `id` of one of the options.
    case chosen(String)
    /// Withdrawn without a choice: the turn was stopped, or the agent no longer needs it.
    case dismissed
  }
}

/// A question about a passage whose answer is still arriving. Once it has arrived it is saved in the
/// note as an exchange and leaves this list.
public struct PendingAnswer: Hashable, Codable, Sendable {
  public let note: EntityID
  public let mentor: EntityID
  public let question: String
  public let askedAt: Timestamp
  /// The answer so far.
  public let answer: String
  /// Why no answer will come. The question stays listed so the person sees it failed.
  public let failure: String?

  public init(
    note: EntityID, mentor: EntityID, question: String, askedAt: Timestamp, answer: String, failure: String?
  ) {
    self.note = note
    self.mentor = mentor
    self.question = question
    self.askedAt = askedAt
    self.answer = answer
    self.failure = failure
  }
}
