import Foundation
import GRDB
import LociModel

extension StoreDatabase {
  /// The notes on one piece of content, in the order they were first saved.
  public func notes(on content: ContentRef) throws -> [Note] {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT document FROM note WHERE content = ? ORDER BY position",
        arguments: [ContentKey.key(content)]
      ).compactMap { document in
        guard case .saved(let note) = try JSONDecoder().decode(NoteEntry.self, from: Data(document.utf8)) else {
          return nil
        }
        return note
      }
    }
  }
}

extension StoreDatabase {
  /// Every item, newest first.
  public func items() throws -> [Item] {
    try documents(Item.self, sql: "SELECT document FROM item ORDER BY id DESC")
  }

  private func documents<Value: Decodable>(_ type: Value.Type, sql: String) throws -> [Value] {
    try queue.read { db in
      try String.fetchAll(db, sql: sql).map { try JSONDecoder().decode(type, from: Data($0.utf8)) }
    }
  }
}
