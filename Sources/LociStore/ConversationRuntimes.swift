import Foundation
import GRDB
import LociModel

/// The conversations that chose their own runtime rather than their kind's default. It lives in the database
/// only and goes with the conversation.
extension StoreDatabase {
  /// `nil` while the conversation follows its kind's default.
  public func runtime(of conversation: ConversationRef) throws -> Runtime? {
    try queue.read { db in
      try Row.fetchOne(
        db, sql: "SELECT provider, model, effort FROM conversation_runtime WHERE owner = ?",
        arguments: [SessionOwner.conversation(conversation).key]
      ).flatMap(Self.runtime)
    }
  }

  public func setRuntime(_ runtime: Runtime, of conversation: ConversationRef, at time: Timestamp) throws {
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO conversation_runtime (owner, provider, model, effort, chosen) VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(owner) DO UPDATE SET provider = excluded.provider, model = excluded.model,
            effort = excluded.effort, chosen = excluded.chosen
          """,
        arguments: [
          SessionOwner.conversation(conversation).key, runtime.provider.rawValue, runtime.model,
          runtime.effort?.rawValue, time.millisecondsSince1970,
        ])
    }
  }

  /// Lets the conversation follow its kind's default again.
  public func clearRuntime(of conversation: ConversationRef) throws {
    try queue.write { db in
      try db.execute(
        sql: "DELETE FROM conversation_runtime WHERE owner = ?",
        arguments: [SessionOwner.conversation(conversation).key])
    }
  }

  /// Every conversation with a runtime of its own, the most recently chosen first.
  public func ownRuntimes() throws -> [(conversation: ConversationRef, runtime: Runtime)] {
    try queue.read { db in
      try Row.fetchAll(
        db, sql: "SELECT owner, provider, model, effort FROM conversation_runtime ORDER BY chosen DESC, owner"
      ).compactMap { row in
        guard case .conversation(let conversation) = SessionOwner(key: row["owner"]), let runtime = Self.runtime(row)
        else { return nil }
        return (conversation, runtime)
      }
    }
  }

  /// Lets every conversation whose own runtime is its kind's default follow the default.
  public func dropRuntimes(equalTo defaults: [ConversationKind: Runtime]) throws {
    for (conversation, runtime) in try ownRuntimes() where defaults[conversation.kind] == runtime {
      try clearRuntime(of: conversation)
    }
  }

  private static func runtime(_ row: Row) -> Runtime? {
    guard let provider = Provider(rawValue: row["provider"]) else { return nil }
    let effort: String? = row["effort"]
    return Runtime(provider: provider, model: row["model"], effort: effort.flatMap(ThinkingEffort.init))
  }
}
