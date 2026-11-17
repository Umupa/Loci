import LociModel

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
