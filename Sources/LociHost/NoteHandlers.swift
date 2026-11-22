import LociModel
import LociStore

extension LocalHost {
  /// Read from the notes file, which always wins over the database.
  public func notes(on content: ContentRef) async throws(HostError) -> [Note] {
    store.notes(on: content).value
  }

  public func addNote(_ command: AddNote) async throws(HostError) -> Note {
    let note = try attempt {
      try Note(
        id: environment.newID(), locator: command.locator, excerpt: command.excerpt.flatMap(Self.text),
        thought: command.thought.flatMap(Self.text), savedAt: environment.now())
    }
    let saved = try await save(note)
    if case .item(let item) = note.locator.content { await happened(.highlighted(item, note: note.id)) }
    return saved
  }

  public func setNoteThought(_ command: SetNoteThought) async throws(HostError) -> Note {
    guard let note = store.notes(on: command.content).value.first(where: { $0.id == command.note }) else {
      throw .notFound(command.note.description)
    }
    let changed = try attempt {
      try Note(
        id: note.id, locator: note.locator, excerpt: note.excerpt, thought: command.thought.flatMap(Self.text),
        exchanges: note.exchanges, savedAt: environment.now())
    }
    return try await save(changed)
  }

  public func deleteNote(_ command: DeleteNote) async throws(HostError) -> Done {
    guard store.notes(on: command.content).value.contains(where: { $0.id == command.note }) else {
      throw .notFound(command.note.description)
    }
    try await appendNote(.deleted(command.note, at: environment.now()), on: command.content)
    return Done()
  }

  private func save(_ note: Note) async throws(HostError) -> Note {
    try await appendNote(.saved(note), on: note.locator.content)
    return note
  }

  private func appendNote(_ entry: NoteEntry, on content: ContentRef) async throws(HostError) {
    if case .lesson(let course, _) = content {
      try await courses.append(entry, on: content, course: course)
    } else {
      try attempt { try store.append(entry, on: content) }
    }
    await follow([.notes(content)])
  }

  /// Text with something in it, trimmed; blank text means none.
  private static func text(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
