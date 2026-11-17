/// The agent asks before going on; the turn waits for `AgentSession.answer`.
public struct PermissionRequest: Hashable, Sendable {
  public struct ID: Hashable, Sendable {
    public let value: String

    public init(_ value: String) {
      self.value = value
    }
  }

  public struct Option: Hashable, Sendable {
    public enum Role: Hashable, Sendable {
      case allow
      case allowAlways
      case deny
      case denyAlways
      /// One of several answers the provider offers, with no allow or deny meaning.
      case choice
    }

    public let id: String
    public let role: Role
    /// The provider's own wording, when it has one.
    public let label: String?

    public init(id: String, role: Role, label: String? = nil) {
      self.id = id
      self.role = role
      self.label = label
    }
  }

  public let id: ID
  public let title: String
  /// The tool call waiting on this answer, when the provider says which one.
  public let toolCall: ToolCall.ID?
  public let options: [Option]

  public init(id: ID, title: String, toolCall: ToolCall.ID? = nil, options: [Option]) {
    self.id = id
    self.title = title
    self.toolCall = toolCall
    self.options = options
  }
}

public enum PermissionAnswer: Hashable, Sendable {
  /// The `id` of one of the request's options.
  case chosen(String)
  case dismissed
}
