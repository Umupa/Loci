import Foundation
import GRDB
import LociModel

/// One session with a mentor's agent. A mentor has a new one when its old session cannot be resumed.
public struct ConversationRecord: Hashable, Sendable {
  public let id: EntityID
  public let mentor: EntityID
  public let provider: Mentor.Provider
  /// The provider's own name for the session, once it has started.
  public let session: String?

  public init(id: EntityID, mentor: EntityID, provider: Mentor.Provider, session: String?) {
    self.id = id
    self.mentor = mentor
    self.provider = provider
    self.session = session
  }
}

extension StoreDatabase {
  /// The mentor's most recent conversation.
  public func latestConversation(of mentor: EntityID) throws -> ConversationRecord? {
    try queue.read { db in
      guard
        let row = try Row.fetchOne(
          db, sql: "SELECT id, provider, session FROM conversation WHERE mentor_id = ? ORDER BY seq DESC LIMIT 1",
          arguments: [mentor.description])
      else { return nil }
      let id: String = row["id"]
      let provider: String = row["provider"]
      guard let id = EntityID(canonical: id), let provider = Mentor.Provider(rawValue: provider) else { return nil }
      return ConversationRecord(id: id, mentor: mentor, provider: provider, session: row["session"])
    }
  }

  public func start(_ conversation: ConversationRecord, at time: Timestamp) throws {
    try queue.write { db in
      try db.execute(
        sql: "INSERT INTO conversation (id, mentor_id, provider, session, started_at) VALUES (?, ?, ?, ?, ?)",
        arguments: [
          conversation.id.description, conversation.mentor.description, conversation.provider.rawValue,
          conversation.session, time.description,
        ])
    }
  }

  public func bind(session: String, to conversation: EntityID) throws {
    try queue.write { db in
      try db.execute(
        sql: "UPDATE conversation SET session = ? WHERE id = ?", arguments: [session, conversation.description])
    }
  }

  /// Adds messages after every message already in the conversation, all of them or none.
  public func append(_ messages: [Message], to conversation: EntityID) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let rows = try messages.map { ($0, String(decoding: try encoder.encode($0.body), as: UTF8.self)) }
    try queue.write { db in
      for (message, body) in rows {
        try db.execute(
          sql: "INSERT INTO message (id, conversation_id, at, body) VALUES (?, ?, ?, ?)",
          arguments: [message.id.description, conversation.description, message.at.description, body])
      }
    }
  }

  /// Every message of every one of the mentor's conversations, oldest first. A row that cannot be read is
  /// left out rather than hiding the rest.
  public func messages(of mentor: EntityID) throws -> [Message] {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT m.id, m.at, m.body FROM message m JOIN conversation c ON c.id = m.conversation_id
          WHERE c.mentor_id = ? ORDER BY m.seq
          """,
        arguments: [mentor.description]
      ).compactMap { row in
        let id: String = row["id"]
        let at: String = row["at"]
        let body: String = row["body"]
        guard let id = EntityID(canonical: id), let at = Timestamp(at),
          let body = try? JSONDecoder().decode(Message.Body.self, from: Data(body.utf8))
        else { return nil }
        return Message(id: id, at: at, body: body)
      }
    }
  }

  /// Conversations go only when their mentor does.
  public func deleteConversations(of mentor: EntityID) throws {
    try queue.write { db in
      try db.execute(
        sql: "DELETE FROM message WHERE conversation_id IN (SELECT id FROM conversation WHERE mentor_id = ?)",
        arguments: [mentor.description])
      try db.execute(sql: "DELETE FROM conversation WHERE mentor_id = ?", arguments: [mentor.description])
    }
  }
}
