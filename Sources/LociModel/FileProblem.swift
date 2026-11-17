/// A file that could not be used, and why. The rest of the folder stays usable.
public struct FileProblem: Hashable, Codable, Sendable {
  /// Relative to the Loci folder, such as `mentors/diao-du-019a…/catalog.yaml`.
  public let path: String
  public let kind: Kind
  /// Details for logs and for the agent that wrote the file. Shown text comes from `kind`.
  public let reason: String
  /// Whose file it is, when that is known. Reading that mentor, item or notes again replaces its problems.
  public let subject: Subject?

  public init(path: String, kind: Kind, reason: String, subject: Subject? = nil) {
    self.path = path
    self.kind = kind
    self.reason = reason
    self.subject = subject
  }

  /// The same problem, belonging to `subject`.
  public func attributed(to subject: Subject?) -> FileProblem {
    FileProblem(path: path, kind: kind, reason: reason, subject: subject)
  }

  public enum Kind: Hashable, Codable, Sendable {
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

  public enum Subject: Hashable, Codable, Sendable {
    case mentor(EntityID)
    case item(EntityID)
    case notes(ContentRef)
  }
}
