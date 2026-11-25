import Foundation
import GRDB
import LociModel

/// The next-up cards (`next_up`), one per key in each home and kept after they leave the deck so a declined
/// one stays declined, and the reminder conditions (`next_up_condition`). They live in the database only.
extension StoreDatabase {
  public func nextUps(of homes: [Home]) throws -> [NextUp] {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT body FROM next_up WHERE home IN (\(homes.map { _ in "?" }.joined(separator: ",")))",
        arguments: StatementArguments(homes.map(Self.column))
      ).compactMap { try? Self.decoded(NextUp.self, $0) }
    }
  }

  public func nextUp(_ id: EntityID) throws -> NextUp? {
    try queue.read { db in
      try String.fetchOne(db, sql: "SELECT body FROM next_up WHERE id = ?", arguments: [id.description])
        .flatMap { try? Self.decoded(NextUp.self, $0) }
    }
  }

  public func nextUp(withKey key: String, in home: Home) throws -> NextUp? {
    try queue.read { db in
      try String.fetchOne(
        db, sql: "SELECT body FROM next_up WHERE home = ? AND key = ?", arguments: [Self.column(home), key]
      ).flatMap { try? Self.decoded(NextUp.self, $0) }
    }
  }

  /// Adds the card, or writes over the one with its id.
  public func saveNextUp(_ card: NextUp) throws {
    let body = try MirrorUpdate.json(card)
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO next_up (id, home, key, body) VALUES (?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET body = excluded.body
          """,
        arguments: [card.id.description, Self.column(card.home), card.key, body])
    }
  }

  /// Cards put off until `now` or before, to bring back to the top.
  public func nextUpsDue(at now: Timestamp) throws -> [NextUp] {
    try queue.read { db in
      try String.fetchAll(db, sql: "SELECT body FROM next_up WHERE json_extract(body, '$.state.later') IS NOT NULL")
        .compactMap { try? Self.decoded(NextUp.self, $0) }
        .filter { if case .later(let until) = $0.state { until <= now } else { false } }
    }
  }

  public func nextUpConditions(of home: Home) throws -> [NextUpCondition] {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT body FROM next_up_condition WHERE home = ? ORDER BY id", arguments: [Self.column(home)]
      ).compactMap { try? Self.decoded(NextUpCondition.self, $0) }
    }
  }

  /// The conditions that watch the source.
  public func nextUpConditions(on source: SourceKey) throws -> [NextUpCondition] {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT body FROM next_up_condition WHERE source = ? ORDER BY id", arguments: [source.description]
      ).compactMap { try? Self.decoded(NextUpCondition.self, $0) }
    }
  }

  public func saveNextUpCondition(_ condition: NextUpCondition) throws {
    let body = try MirrorUpdate.json(condition)
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO next_up_condition (id, home, source, body) VALUES (?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET body = excluded.body
          """,
        arguments: [condition.id.description, Self.column(condition.home), condition.source.description, body])
    }
  }

  /// `false` when there was no such condition.
  @discardableResult
  public func removeNextUpCondition(_ id: EntityID) throws -> Bool {
    try queue.write { db in
      try db.execute(sql: "DELETE FROM next_up_condition WHERE id = ?", arguments: [id.description])
      return db.changesCount > 0
    }
  }

  /// Forgets a project's cards and conditions, as when it is deleted for good.
  public func forgetNextUps(of project: Project.ID) throws {
    let home = Self.column(.project(project))
    try queue.write { db in
      try db.execute(sql: "DELETE FROM next_up WHERE home = ?", arguments: [home])
      try db.execute(sql: "DELETE FROM next_up_condition WHERE home = ?", arguments: [home])
    }
  }

  private static func column(_ home: Home) -> String {
    switch home {
    case .chat: "chat"
    case .project(let id): id.description
    }
  }
}
