import Foundation
import GRDB
import LociModel

/// What the files say about one item or notes file, read before the write transaction starts.
/// Rebuilding and following changes both write through these, so they cannot drift apart.
enum MirrorUpdate: Sendable {
  case item(EntityID, Item?, content: String?)
  case notes(ContentRef, [Note])

  func write(_ db: Database) throws {
    switch self {
    case .item(let id, let item, let content):
      try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [id.description])
      try Self.unindex(owner: ContentKey.key(.item(id)), db)
      if let item { try Self.insert(item, content: content, db) }
    case .notes(let content, let notes):
      let key = ContentKey.key(content)
      try db.execute(sql: "DELETE FROM note WHERE content = ?", arguments: [key])
      try Self.unindex(owner: ContentKey.notes(content), db)
      for (position, note) in notes.enumerated() { try Self.insert(note, on: content, at: position, db) }
    }
  }

  private static func insert(_ item: Item, content: String?, _ db: Database) throws {
    try db.execute(
      sql: "INSERT INTO item (id, kind, title, document) VALUES (?, ?, ?, ?)",
      arguments: [item.id.description, item.kindName, item.title, try json(item)])
    let key = ContentKey.key(.item(item.id))
    try index(owner: key, target: key, field: .title, item.title, db)
    if let content { try index(owner: key, target: key, field: .body, content, db) }
  }

  private static func insert(_ note: Note, on content: ContentRef, at position: Int, _ db: Database) throws {
    try db.execute(
      sql: "INSERT INTO note (id, content, position, document) VALUES (?, ?, ?, ?)",
      arguments: [note.id.description, ContentKey.key(content), position, try json(NoteEntry.saved(note))])
    let text = ([note.excerpt, note.thought].compactMap(\.self) + note.exchanges.flatMap { [$0.question, $0.answer] })
      .joined(separator: "\n")
    guard !text.isEmpty else { return }
    try index(
      owner: ContentKey.notes(content), target: "note/\(note.id)", field: .note, text, locator: note.locator, db)
  }

  /// Search rows are found by owner through `search_owner`: FTS5 cannot index its own columns, so
  /// deleting by an FTS5 column would scan the whole index on every change.
  private static func unindex(owner: String, _ db: Database) throws {
    try db.execute(
      sql: "DELETE FROM search WHERE rowid IN (SELECT search_rowid FROM search_owner WHERE owner = ?)",
      arguments: [owner])
    try db.execute(sql: "DELETE FROM search_owner WHERE owner = ?", arguments: [owner])
  }

  private static func index(
    owner: String, target: String, field: SearchHit.Field, _ text: String, locator: Locator? = nil, _ db: Database
  ) throws {
    try db.cachedStatement(sql: "INSERT INTO search (target, field, original, locator, text) VALUES (?, ?, ?, ?, ?)")
      .execute(arguments: [target, field.rawValue, text, locator?.description, SearchText.indexed(text)])
    try db.cachedStatement(sql: "INSERT INTO search_owner (search_rowid, owner) VALUES (?, ?)")
      .execute(arguments: [db.lastInsertedRowID, owner])
  }

  static func json(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}

extension Item {
  var kindName: String {
    switch kind {
    case .article: "article"
    case .paper: "paper"
    case .video: "video"
    case .audio: "audio"
    case .repository: "repository"
    }
  }
}
