import LociModel

/// A file that could not be used, and why. The rest of the folder stays usable.
public struct FileProblem: Hashable, Sendable {
  /// Relative to the store's root, such as `mentors/diao-du-019a…/catalog.yaml`.
  public let path: String
  public let kind: Kind
  /// Details for logs and for the agent that wrote the file. Shown text comes from `kind`.
  public let reason: String

  public init(path: String, kind: Kind, reason: String) {
    self.path = path
    self.kind = kind
    self.reason = reason
  }

  public enum Kind: Hashable, Sendable {
    /// The bytes could not be read as text.
    case unreadable
    /// The text does not describe a valid value.
    case invalid
    /// Another folder already holds the same id; this one is ignored.
    case duplicateID
    /// A lesson file whose name is not a slug.
    case misnamed
    /// A note line that points into different content than the file it is in.
    case misplacedNote
    /// A `loci://` link in a lesson that does not parse.
    case brokenLocator
  }
}

/// A value read from files, with the problems met while reading it.
public struct Loaded<Value: Sendable>: Sendable {
  public let value: Value
  public let problems: [FileProblem]
}

extension Loaded: Equatable where Value: Equatable {}

public enum StoreError: Error, Equatable {
  /// Nothing at that place; the path is relative to the root, or names the id looked for.
  case notFound(String)
  case alreadyExists(EntityID)
  case invalid(FileProblem)
  /// A note whose locator points into other content than the notes file it was appended to.
  case misplacedNote(EntityID)
}
