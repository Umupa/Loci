import Foundation
import GRDB
import LociModel

/// What each conversation runs on, once it was chosen there or its first session opened. It lives in the
/// database only and goes with the conversation.
extension StoreDatabase {
  /// `nil` until the conversation has a runtime of its own.
  public func runtime(of conversation: ConversationRef) throws -> Runtime? {
    try queue.read { db in
      guard
        let row = try Row.fetchOne(
          db, sql: "SELECT provider, model, effort FROM conversation_runtime WHERE owner = ?",
          arguments: [SessionOwner.conversation(conversation).key]),
        let provider = Provider(rawValue: row["provider"])
      else { return nil }
      let effort: String? = row["effort"]
      return Runtime(provider: provider, model: row["model"], effort: effort.flatMap(ThinkingEffort.init))
    }
  }

  public func setRuntime(_ runtime: Runtime, of conversation: ConversationRef) throws {
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO conversation_runtime (owner, provider, model, effort) VALUES (?, ?, ?, ?)
          ON CONFLICT(owner) DO UPDATE SET provider = excluded.provider, model = excluded.model,
            effort = excluded.effort
          """,
        arguments: [
          SessionOwner.conversation(conversation).key, runtime.provider.rawValue, runtime.model,
          runtime.effort?.rawValue,
        ])
    }
  }
}
