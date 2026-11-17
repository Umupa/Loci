public struct ToolCall: Hashable, Sendable {
  public struct ID: Hashable, Sendable {
    public let value: String

    public init(_ value: String) {
      self.value = value
    }
  }

  public enum Kind: Hashable, Sendable {
    case read
    case edit
    case execute
    case search
    case other
  }

  public enum Change: Hashable, Sendable {
    /// The complete arguments, replacing what was known.
    case input(JSONValue)
    case running
    /// Everything the tool has printed so far, replacing what was known.
    case output(String)
    case finished(output: String, failed: Bool)
  }

  public let id: ID
  /// The provider's own name for the tool.
  public let name: String
  public let kind: Kind
  public let input: JSONValue

  public init(id: ID, name: String, kind: Kind, input: JSONValue) {
    self.id = id
    self.name = name
    self.kind = kind
    self.input = input
  }
}
