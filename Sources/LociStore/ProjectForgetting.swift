import Foundation
import GRDB
import LociModel

/// What the database keeps of a project, gone in one write when it is deleted for good: so a deletion either
/// leaves nothing behind or, failing, leaves everything to be tried again.
extension StoreDatabase {
  /// Forgets the project's conversation and its runs' sessions, its schedules, follow-ups, inbox events, runs,
  /// the connector calls of its conversation, runs and sources, the search over its conversations and run
  /// records, its sources, cards and conditions. A card whose approval was being written or undone stays until
  /// the app learns what became of it, so nothing written is lost track of.
  public func forgetProject(_ project: Project.ID) throws {
    let home = Home.project(project)
    let folder = home.folder + "%"
    try queue.write { db in
      let runs = try Self.bodies(of: Run.self, sql: "SELECT body FROM run", in: db)
        .filter { $0.kind.home == home }.map(\.id)
      let owners = [SessionOwner.conversation(.project(project))] + runs.map(SessionOwner.run)
      for owner in owners.map(\.key) {
        try db.execute(
          sql: "DELETE FROM message WHERE session_id IN (SELECT id FROM session WHERE owner = ?)", arguments: [owner])
        try db.execute(sql: "DELETE FROM session WHERE owner = ?", arguments: [owner])
      }
      for run in runs {
        try db.execute(sql: "DELETE FROM run_schedule WHERE run_id = ?", arguments: [run.description])
        try db.execute(sql: "DELETE FROM run WHERE id = ?", arguments: [run.description])
        try db.execute(
          sql: "DELETE FROM connector_call WHERE caller = ?", arguments: [ConnectorCall.Caller.run(run).tag])
      }
      try db.execute(
        sql: "DELETE FROM connector_call WHERE caller = ?",
        arguments: [ConnectorCall.Caller.conversation(.project(project)).tag])
      let schedules = try Self.bodies(of: Schedule.self, sql: "SELECT body FROM timer WHERE kind = 'schedule'", in: db)
        .filter { $0.home == home }.map(\.id.description)
      let followUps = try Self.bodies(of: FollowUp.self, sql: "SELECT body FROM timer WHERE kind = 'follow-up'", in: db)
        .filter { $0.home == home }.map(\.id.description)
      for id in schedules + followUps { try db.execute(sql: "DELETE FROM timer WHERE id = ?", arguments: [id]) }
      let events = try Self.bodies(of: Event.self, sql: "SELECT body FROM inbox", in: db)
        .filter { $0.source.home == home }.map(\.id.description)
      for id in events { try db.execute(sql: "DELETE FROM inbox WHERE id = ?", arguments: [id]) }
      try db.execute(
        sql: "DELETE FROM transcript WHERE rowid IN (SELECT transcript_rowid FROM transcript_file WHERE path LIKE ?)",
        arguments: [folder])
      try db.execute(sql: "DELETE FROM transcript_file WHERE path LIKE ?", arguments: [folder])
      try db.execute(
        sql: "DELETE FROM connector_call WHERE caller LIKE ?",
        arguments: [ConnectorCall.Caller.source(SourceKey(home, "")).tag + "%"])
      for table in ["source_snapshot", "source_series", "source_entry"] {
        try db.execute(sql: "DELETE FROM \(table) WHERE source LIKE ?", arguments: [folder])
      }
      try db.execute(
        sql: """
          DELETE FROM next_up WHERE home = ?
          AND json_extract(body, '$.execution.writing') IS NULL AND json_extract(body, '$.execution.undoing') IS NULL
          """,
        arguments: [project.description])
      try db.execute(sql: "DELETE FROM next_up_condition WHERE home = ?", arguments: [project.description])
    }
  }

  private static func bodies<Value: Decodable>(of type: Value.Type, sql: String, in db: Database) throws -> [Value] {
    try String.fetchAll(db, sql: sql).compactMap { try? decoded(type, $0) }
  }
}
