import Foundation
import GRDB
import LociModel

extension StoreDatabase {
  public func readingState(of content: ContentRef) throws -> ReadingState? {
    try queue.read { db in
      guard
        let row = try Row.fetchOne(
          db, sql: "SELECT position, finished, updated_at FROM reading_state WHERE content = ?",
          arguments: [ContentKey.key(content)])
      else { return nil }
      let position: String? = row["position"]
      let updatedAt: String = row["updated_at"]
      guard let timestamp = Timestamp(updatedAt) else { return nil }
      return ReadingState(position: position.flatMap(Locator.init), finished: row["finished"], updatedAt: timestamp)
    }
  }

  /// Throws `misplacedPosition` when the position points into other content.
  public func save(_ state: ReadingState, for content: ContentRef) throws {
    if let position = state.position, position.content != content {
      throw StoreDatabaseError.misplacedPosition(position)
    }
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO reading_state (content, position, finished, updated_at) VALUES (?, ?, ?, ?)
          ON CONFLICT(content) DO UPDATE SET
            position = excluded.position, finished = excluded.finished, updated_at = excluded.updated_at
          """,
        arguments: [
          ContentKey.key(content), state.position?.description, state.finished, state.updatedAt.description,
        ])
    }
  }
}

public enum StoreDatabaseError: Error, Equatable {
  /// A reading position that points into other content than the one it is saved for.
  case misplacedPosition(Locator)
  /// The day was looked back on already.
  case alreadyReviewed(Day)
}

extension StoreDatabase {
  /// The content read most recently, and when.
  public func latestReading() throws -> (content: ContentRef, at: Timestamp)? {
    try queue.read { db in
      guard
        let row = try Row.fetchOne(
          db, sql: "SELECT content, updated_at FROM reading_state ORDER BY updated_at DESC LIMIT 1"),
        let content = ContentKey.content(row["content"]), let at = Timestamp(row["updated_at"] as String)
      else { return nil }
      return (content, at)
    }
  }
}
