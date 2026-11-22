/// Every note on one piece of content, in the order they were first saved, kept current.
public struct NotesOn: Subscription {
  public static let name = "notes"
  public let content: ContentRef

  public init(content: ContentRef) {
    self.content = content
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> [Note] {
    try await handler.notes(on: content)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    if case .lesson(let course, _) = content, changes.contains(.course(course)) { return true }
    return changes.contains(.notes(content)) || changes.contains(.everything)
  }
}

/// Leaves a note on a passage: a highlight, with a thought if there is one.
public struct AddNote: RemoteCommand {
  public static let name = "note.add"
  public let locator: Locator
  /// The words that were marked, as the reader saw them.
  public let excerpt: String?
  public let thought: String?

  public init(locator: Locator, excerpt: String?, thought: String? = nil) {
    self.locator = locator
    self.excerpt = excerpt
    self.thought = thought
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Note {
    try await handler.addNote(self)
  }
}

/// Writes, changes or, with `nil`, removes a note's thought. Its place and questions stay as they are.
public struct SetNoteThought: RemoteCommand {
  public static let name = "note.thought"
  public let content: ContentRef
  public let note: EntityID
  public let thought: String?

  public init(content: ContentRef, note: EntityID, thought: String?) {
    self.content = content
    self.note = note
    self.thought = thought
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Note {
    try await handler.setNoteThought(self)
  }
}

public struct DeleteNote: RemoteCommand {
  public static let name = "note.delete"
  public let content: ContentRef
  public let note: EntityID

  public init(content: ContentRef, note: EntityID) {
    self.content = content
    self.note = note
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.deleteNote(self)
  }
}
