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

extension StoreDatabase {
  /// Remembers the text of a lesson as the reader saw it, and returns what they saw before when it differs.
  ///
  /// The first time a lesson is seen there is nothing to compare with, so it counts as unchanged.
  public func see(_ text: String, of lesson: LessonRef) throws -> String? {
    let key = ContentKey.key(.lesson(lesson))
    return try queue.write { db in
      let before = try String.fetchOne(db, sql: "SELECT text FROM seen_lesson WHERE content = ?", arguments: [key])
      try db.execute(
        sql:
          "INSERT INTO seen_lesson (content, text) VALUES (?, ?) ON CONFLICT(content) DO UPDATE SET text = excluded.text",
        arguments: [key, text])
      return before == text ? nil : before
    }
  }

  /// What the reader has read and seen of one mentor's lessons: the lessons read to the end, and the text
  /// last seen of each lesson.
  public func readingRecord(of mentor: EntityID) throws -> (read: Set<Lesson.Slug>, seen: [Lesson.Slug: String]) {
    let prefix = ContentKey.mentor(mentor) + "/lesson/"
    return try queue.read { db in
      var read = Set<Lesson.Slug>()
      for key in try String.fetchAll(
        db, sql: "SELECT content FROM reading_state WHERE finished AND substr(content, 1, ?) = ?",
        arguments: [prefix.count, prefix])
      {
        if case .lesson(let lesson) = ContentKey.content(key) { read.insert(lesson.lesson) }
      }
      var seen: [Lesson.Slug: String] = [:]
      for row in try Row.fetchAll(
        db, sql: "SELECT content, text FROM seen_lesson WHERE substr(content, 1, ?) = ?",
        arguments: [prefix.count, prefix])
      {
        if case .lesson(let lesson) = ContentKey.content(row["content"]) { seen[lesson.lesson] = row["text"] }
      }
      return (read, seen)
    }
  }
}

public enum StoreDatabaseError: Error, Equatable {
  /// A reading position that points into other content than the one it is saved for.
  case misplacedPosition(Locator)
}
