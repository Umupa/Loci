import Foundation
import GRDB
import LociModel

/// The timers the companion set: schedules, and follow-ups until they come due or are cancelled. They live
/// in the database only; a panel's refresh lives in the panel's file.
extension StoreDatabase {
  public func schedules() throws -> [Schedule] {
    try queue.read { db in
      try String.fetchAll(db, sql: "SELECT body FROM timer WHERE kind = 'schedule' ORDER BY name")
        .compactMap { try? Self.decoded(Schedule.self, $0) }
    }
  }

  public func schedule(_ id: EntityID) throws -> Schedule? {
    try queue.read { db in
      try String.fetchOne(
        db, sql: "SELECT body FROM timer WHERE id = ? AND kind = 'schedule'", arguments: [id.description]
      )
      .flatMap { try? Self.decoded(Schedule.self, $0) }
    }
  }

  /// Adds the schedule, or writes over the one with its id. Throws when another schedule has its name.
  public func saveSchedule(_ schedule: Schedule) throws {
    let body = try MirrorUpdate.json(schedule)
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO timer (id, kind, name, body) VALUES (?, 'schedule', ?, ?)
          ON CONFLICT(id) DO UPDATE SET name = excluded.name, body = excluded.body
          """,
        arguments: [schedule.id.description, schedule.name, body])
    }
  }

  public func removeSchedule(_ id: EntityID) throws {
    try queue.write { db in
      try db.execute(sql: "DELETE FROM timer WHERE id = ? AND kind = 'schedule'", arguments: [id.description])
    }
  }

  public func addFollowUp(_ followUp: FollowUp) throws {
    let body = try MirrorUpdate.json(followUp)
    try queue.write { db in
      try db.execute(
        sql: "INSERT INTO timer (id, kind, body, due_at) VALUES (?, 'follow-up', ?, ?)",
        arguments: [followUp.id.description, body, followUp.due.description])
    }
  }

  /// The follow-ups still to come due, soonest first.
  public func followUps() throws -> [FollowUp] {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT body FROM timer WHERE kind = 'follow-up' AND ended_at IS NULL ORDER BY due_at, id"
      ).compactMap { try? Self.decoded(FollowUp.self, $0) }
    }
  }

  /// A follow-up, also one that came due or was cancelled.
  public func followUp(_ id: EntityID) throws -> FollowUp? {
    try queue.read { db in
      try String.fetchOne(
        db, sql: "SELECT body FROM timer WHERE id = ? AND kind = 'follow-up'", arguments: [id.description]
      ).flatMap { try? Self.decoded(FollowUp.self, $0) }
    }
  }

  /// Takes the follow-up off the list, as come due or cancelled. `false` when it was off the list already.
  @discardableResult
  public func endFollowUp(_ id: EntityID, at moment: Timestamp) throws -> Bool {
    try queue.write { db in
      try db.execute(
        sql: "UPDATE timer SET ended_at = ? WHERE id = ? AND kind = 'follow-up' AND ended_at IS NULL",
        arguments: [moment.description, id.description])
      return db.changesCount > 0
    }
  }

  static func decoded<Value: Decodable>(_ type: Value.Type, _ text: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(text.utf8))
  }
}
