import Foundation
import GRDB
import LociModel

/// The next-up cards (`next_up`), one per key in each home and kept after they leave the deck so a declined
/// one stays declined. They live in the database only.
extension StoreDatabase {
  public func nextUps(of homes: [Home]) throws -> [NextUp] {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT body FROM next_up WHERE home IN (\(homes.map { _ in "?" }.joined(separator: ",")))",
        arguments: StatementArguments(homes.map(Self.column))
      ).compactMap { try? Self.decoded(NextUp.self, $0) }
    }
  }

  /// Every card of every home.
  public func allNextUps() throws -> [NextUp] {
    try queue.read { db in
      try String.fetchAll(db, sql: "SELECT body FROM next_up").compactMap { try? Self.decoded(NextUp.self, $0) }
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
    try queue.write { db in try Self.put(card, body, in: db) }
  }

  /// Changes a card in one write, so two Macs acting on it at once cannot both claim it: `change` sees it as
  /// stored and returns what to store, or `nil` to leave it. Any change is kept one version on. The card as it
  /// was and as it is after; `nil` when there is no such card.
  public func changeNextUp(_ id: EntityID, _ change: (NextUp) -> NextUp?) throws -> (before: NextUp, after: NextUp?)? {
    try queue.write { db in
      guard
        let card = try String.fetchOne(db, sql: "SELECT body FROM next_up WHERE id = ?", arguments: [id.description])
          .flatMap({ try? Self.decoded(NextUp.self, $0) })
      else { return nil }
      guard let changed = change(card) else { return (card, nil) }
      return (card, try Self.keep(changed, over: card, in: db))
    }
  }

  /// Puts the card with the key in one write: `make` sees the one stored, if any, and returns what to store, or
  /// `nil` to leave it. A change is kept one version on. The card as it was and as it is after.
  public func putNextUp(withKey key: String, in home: Home, _ make: (NextUp?) -> NextUp?) throws
    -> (before: NextUp?, after: NextUp?)
  {
    try queue.write { db in
      let card = try String.fetchOne(
        db, sql: "SELECT body FROM next_up WHERE home = ? AND key = ?", arguments: [Self.column(home), key]
      ).flatMap { try? Self.decoded(NextUp.self, $0) }
      guard let made = make(card) else { return (card, nil) }
      guard let card else {
        try Self.put(made, try MirrorUpdate.json(made), in: db)
        return (nil, made)
      }
      return (card, try Self.keep(made, over: card, in: db))
    }
  }

  /// Takes the card away for good.
  public func forgetNextUp(_ id: EntityID) throws {
    try queue.write { db in try db.execute(sql: "DELETE FROM next_up WHERE id = ?", arguments: [id.description]) }
  }

  /// Cards put off until `now` or before, to bring back to the top.
  public func nextUpsDue(at now: Timestamp) throws -> [NextUp] {
    try queue.read { db in
      try String.fetchAll(db, sql: "SELECT body FROM next_up WHERE json_extract(body, '$.place.later') IS NOT NULL")
        .compactMap { try? Self.decoded(NextUp.self, $0) }
        .filter { if case .later(let until) = $0.place { until <= now } else { false } }
    }
  }

  /// Forgets the feedback a daily review read; what came after it waits for the next review.
  public func forgetFeedback(_ read: [EntityID: [NextUp.Feedback]]) throws {
    try queue.write { db in
      for (id, feedback) in read {
        let body = try String.fetchOne(db, sql: "SELECT body FROM next_up WHERE id = ?", arguments: [id.description])
        guard let body, let card = try? Self.decoded(NextUp.self, body) else { continue }
        try Self.put(card, try MirrorUpdate.json(card.reviewed(feedback)), in: db)
      }
    }
  }

  /// `changed` one version on from `card`, stored; `card` as it is when nothing changed.
  private static func keep(_ changed: NextUp, over card: NextUp, in db: Database) throws -> NextUp {
    guard changed.with(version: card.version) != card else { return card }
    let stepped = changed.with(version: card.version + 1)
    try put(stepped, try MirrorUpdate.json(stepped), in: db)
    return stepped
  }

  private static func put(_ card: NextUp, _ body: String, in db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO next_up (id, home, key, body) VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET body = excluded.body
        """,
      arguments: [card.id.description, Self.column(card.home), card.key, body])
  }

  private static func column(_ home: Home) -> String {
    switch home {
    case .chat: "chat"
    case .project(let id): id.description
    }
  }
}
