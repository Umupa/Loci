import Foundation
import GRDB
import LociModel

/// The runs done in the background, filed under the schedules they were for.
extension StoreDatabase {
  /// Adds the run, or writes its new outcome.
  public func saveRun(_ run: Run) throws {
    let body = try MirrorUpdate.json(run)
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO run (id, started_at, body) VALUES (?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET body = excluded.body
          """,
        arguments: [run.id.description, run.startedAt.description, body])
      for schedule in run.kind.sources.compactMap(\.schedule) {
        try db.execute(
          sql: "INSERT OR IGNORE INTO run_schedule (run_id, schedule) VALUES (?, ?)",
          arguments: [run.id.description, schedule.key])
      }
    }
  }

  public func run(_ id: Run.ID) throws -> Run? {
    try queue.read { db in
      try String.fetchOne(db, sql: "SELECT body FROM run WHERE id = ?", arguments: [id.description])
        .flatMap { try? Self.decoded(Run.self, $0) }
    }
  }

  /// The schedule's latest runs, newest first.
  public func runs(of schedule: ScheduleRef, limit: Int) throws -> [Run] {
    try queue.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT run.body FROM run JOIN run_schedule ON run_schedule.run_id = run.id
          WHERE run_schedule.schedule = ? ORDER BY run.started_at DESC, run.id DESC LIMIT ?
          """,
        arguments: [schedule.key, limit]
      ).compactMap { try? Self.decoded(Run.self, $0) }
    }
  }

  /// Runs that started after `moment`, oldest first.
  public func runs(startedAfter moment: Timestamp) throws -> [Run] {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT body FROM run WHERE started_at > ? ORDER BY started_at, id", arguments: [moment.description]
      ).compactMap { try? Self.decoded(Run.self, $0) }
    }
  }

  /// Runs that did a follow-up and are over, whose outcome the main conversation was not yet told.
  public func untoldFollowUpRuns() throws -> [Run] {
    try queue.read { db in
      try String.fetchAll(db, sql: "SELECT body FROM run WHERE told_at IS NULL ORDER BY started_at, id")
        .compactMap { try? Self.decoded(Run.self, $0) }
        .filter { run in
          if case .running = run.outcome { return false }
          return run.kind.sources.contains { if case .followUp = $0 { true } else { false } }
        }
    }
  }

  public func markTold(_ runs: [Run.ID], at moment: Timestamp) throws {
    try queue.write { db in
      for run in runs {
        try db.execute(
          sql: "UPDATE run SET told_at = ? WHERE id = ?", arguments: [moment.description, run.description])
      }
    }
  }
}
