/// An item with its text, as one view shows it.
public struct ItemPage: Hashable, Codable, Sendable {
  public let item: Item
  /// The text of an article or paper; `nil` for kinds read some other way.
  public let text: String?

  public init(item: Item, text: String?) {
    self.item = item
    self.text = text
  }
}

/// Whether the host's storage is sound, and which files it could not use.
public struct Health: Hashable, Codable, Sendable {
  public let database: DatabaseState
  /// The database was replaced when this host started, so reading positions were lost.
  public let readingStateLost: Bool
  public let fileProblems: [FileProblem]

  public init(database: DatabaseState, readingStateLost: Bool, fileProblems: [FileProblem]) {
    self.database = database
    self.readingStateLost = readingStateLost
    self.fileProblems = fileProblems
  }

  public enum DatabaseState: Hashable, Codable, Sendable {
    /// Lists and search may be out of date until the rebuild finishes.
    case rebuilding
    case ready
    /// Lists and search are unavailable; files can still be read.
    case failed(String)
  }
}

/// The reply of a command that has nothing to say beyond having succeeded.
public struct Done: Hashable, Codable, Sendable {
  public init() {}
}
