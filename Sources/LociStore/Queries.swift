import Foundation
import GRDB
import LociModel

extension StoreDatabase {
  /// What one lesson cites, in the order the lesson cites it.
  public func citations(in lesson: LessonRef) throws -> [Citation] {
    try queue.read { db in
      try Row.fetchAll(
        db, sql: "SELECT item_id, anchor FROM citation WHERE mentor_id = ? AND slug = ? ORDER BY position",
        arguments: [lesson.mentor.description, lesson.lesson.description]
      ).compactMap { Self.citation(in: lesson, $0) }
    }
  }

  /// Every lesson, of any mentor, that cites the item.
  public func citations(of item: EntityID) throws -> [Citation] {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql:
          "SELECT mentor_id, slug, item_id, anchor FROM citation WHERE item_id = ? ORDER BY mentor_id, slug, position",
        arguments: [item.description]
      ).compactMap { row in
        guard let mentor = EntityID(canonical: row["mentor_id"]), let slug = Lesson.Slug(row["slug"]) else {
          return nil
        }
        return Self.citation(in: LessonRef(mentor: mentor, lesson: slug), row)
      }
    }
  }

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

  private static func citation(in lesson: LessonRef, _ row: Row) -> Citation? {
    guard let item = EntityID(canonical: row["item_id"]) else { return nil }
    let anchorText: String? = row["anchor"]
    guard let anchorText else { return Citation(lesson: lesson, item: item, anchor: nil) }
    guard case .item(_, let anchor) = Locator(anchorText) else { return nil }
    return Citation(lesson: lesson, item: item, anchor: anchor)
  }
}
