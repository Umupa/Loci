/// What a caller decides about the notes on content it deletes.
public enum NotesOnDelete: Hashable, Codable, Sendable {
  case keep
  case delete
}
