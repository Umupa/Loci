import Foundation
import GRDB
import LociModel

extension StoreDatabase {
  /// Every message every mentor gave or was asked on the item, oldest first, each with the mentor whose
  /// conversation it is in.
  public func messages(on item: EntityID) throws -> [AttributedMessage] {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT m.id, m.at, m.body, c.mentor_id FROM message m JOIN conversation c ON c.id = m.conversation_id
          WHERE c.item_id = ? ORDER BY m.seq
          """,
        arguments: [item.description]
      ).compactMap { row in
        let mentor: String = row["mentor_id"]
        guard let mentor = EntityID(canonical: mentor), let message = Self.message(row) else { return nil }
        return AttributedMessage(mentor: mentor, message: message)
      }
    }
  }

  /// The item's conversations and its companion go with the item.
  public func deleteConversations(on item: EntityID) throws {
    try queue.write { db in
      try db.execute(
        sql: "DELETE FROM message WHERE conversation_id IN (SELECT id FROM conversation WHERE item_id = ?)",
        arguments: [item.description])
      try db.execute(sql: "DELETE FROM conversation WHERE item_id = ?", arguments: [item.description])
      try db.execute(sql: "DELETE FROM companion WHERE item_id = ?", arguments: [item.description])
    }
  }

  /// The mentor last chosen to read along on the item; for an item where none was chosen yet, the one
  /// chosen most recently on any item.
  public func companion(on item: EntityID) throws -> EntityID? {
    try queue.read { db in
      let chosen =
        try String.fetchOne(db, sql: "SELECT mentor_id FROM companion WHERE item_id = ?", arguments: [item.description])
        ?? String.fetchOne(db, sql: "SELECT mentor_id FROM companion ORDER BY chosen_at DESC, rowid DESC LIMIT 1")
      return chosen.flatMap(EntityID.init(canonical:))
    }
  }

  /// The choice is written as a new row, so among choices made at the same moment the last one counts.
  public func choose(companion mentor: EntityID, on item: EntityID, at time: Timestamp) throws {
    try queue.write { db in
      try db.execute(sql: "DELETE FROM companion WHERE item_id = ?", arguments: [item.description])
      try db.execute(
        sql: "INSERT INTO companion (item_id, mentor_id, chosen_at) VALUES (?, ?, ?)",
        arguments: [item.description, mentor.description, time.description])
    }
  }
}
