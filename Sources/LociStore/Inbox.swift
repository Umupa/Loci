import Foundation
import GRDB
import LociModel

/// The inbox: everything to do in the background, kept until a run has done it, so nothing is lost when
/// the app quits or the Mac sleeps. One event for each key.
extension StoreDatabase {
  /// Puts the event in the inbox unless one with its key is there. Whether it was put.
  @discardableResult
  public func raise(_ event: Event) throws -> Bool {
    try queue.write { db in try Self.raise(event, in: db) }
  }

  static func raise(_ event: Event, in db: Database) throws -> Bool {
    try db.execute(
      sql: "INSERT OR IGNORE INTO inbox (id, key, open, body) VALUES (?, ?, ?, ?)",
      arguments: [event.id.description, event.key, event.state.isOpen, try MirrorUpdate.json(event)])
    return db.changesCount > 0
  }

  /// How many of the home's events that count toward its watch budget started a run after `cutoff`.
  public func wakeUps(in home: Home, since cutoff: Timestamp) throws -> Int {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT body FROM inbox WHERE json_extract(body, '$.wokeAt') > ?",
        arguments: [cutoff.description]
      ).lazy.compactMap { try? Self.decoded(Event.self, $0) }.filter { $0.source.home == home }.count
    }
  }

  /// Events waiting or running, in the order they were raised.
  public func openEvents() throws -> [Event] {
    try queue.read { db in
      try String.fetchAll(db, sql: "SELECT body FROM inbox WHERE open = 1 ORDER BY seq")
        .compactMap { try? Self.decoded(Event.self, $0) }
    }
  }

  /// Whether an event with this key was ever raised, whatever came of it.
  public func hasEvent(withKey key: String) throws -> Bool {
    try queue.read { db in
      try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM inbox WHERE key = ?)", arguments: [key]) ?? false
    }
  }

  public func event(_ id: EntityID) throws -> Event? {
    try queue.read { db in
      try String.fetchOne(db, sql: "SELECT body FROM inbox WHERE id = ?", arguments: [id.description])
        .flatMap { try? Self.decoded(Event.self, $0) }
    }
  }

  /// Writes the event's new state.
  public func update(_ event: Event) throws {
    let body = try MirrorUpdate.json(event)
    try queue.write { db in
      try db.execute(
        sql: "UPDATE inbox SET open = ?, body = ? WHERE id = ?",
        arguments: [event.state.isOpen, body, event.id.description])
    }
  }

  /// Puts events whose run the app quit during back to waiting, to be done again by the same run. Quitting
  /// is not a failed try.
  public func recoverRunning() throws {
    for event in try openEvents() {
      guard case .running(let run, let tries) = event.state else { continue }
      try update(event.with(.waiting(Event.Retry(run: run, tries: tries, notBefore: nil))))
    }
  }
}
