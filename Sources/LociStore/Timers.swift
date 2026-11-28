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

  /// Keeps the follow-up, or returns the one kept before with its key. One with a parent is kept only while the
  /// parent's run goes on, in its home, one level below it and no later than its deadline: checked in the same
  /// write.
  @discardableResult
  public func addFollowUp(_ followUp: FollowUp) throws -> FollowUp {
    let body = try MirrorUpdate.json(followUp)
    return try queue.write { db in
      if let key = followUp.key,
        let earlier = try String.fetchOne(
          db, sql: "SELECT body FROM timer WHERE kind = 'follow-up' AND json_extract(body, '$.key') = ?",
          arguments: [key])
      {
        return try Self.decoded(FollowUp.self, earlier)
      }
      if let id = followUp.parent {
        guard
          let body = try String.fetchOne(db, sql: "SELECT body FROM inbox WHERE id = ?", arguments: [id.description]),
          let parent = try? Self.decoded(Event.self, body), case .running = parent.state,
          parent.source.home == followUp.home, let depth = followUp.depth, depth == parent.depth + 1,
          depth <= Event.deepest
        else { throw HostError.invalidRequest("The parent run is no longer active or cannot create a follow-up.") }
        if let parentDeadline = parent.deadline,
          followUp.deadline.map({ $0 <= parentDeadline }) != true
        {
          throw HostError.invalidRequest("The deadline cannot be later than the parent event's deadline.")
        }
      }
      try db.execute(
        sql: "INSERT INTO timer (id, kind, body, due_at) VALUES (?, 'follow-up', ?, ?)",
        arguments: [followUp.id.description, body, followUp.due.description])
      return followUp
    }
  }

  /// Ends the follow-up and raises its event, as `id`, in one write; one past its deadline is put in the inbox
  /// already dropped. Whether an event was raised.
  public func raiseFollowUp(_ followUp: FollowUp, id: EntityID, at now: Timestamp) throws -> Bool {
    try queue.write { db in
      try db.execute(
        sql: "UPDATE timer SET ended_at = ? WHERE id = ? AND kind = 'follow-up' AND ended_at IS NULL",
        arguments: [now.description, followUp.id.description])
      guard db.changesCount > 0 else { return false }
      let event = Event(
        id: id, source: .followUp(followUp.id, project: followUp.home.project), due: followUp.due,
        deadline: followUp.deadline, parent: followUp.parent, depth: followUp.depth ?? 0)
      return try Self.raise(event.isExpired(at: now) ? event.with(.dropped) : event, in: db)
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
