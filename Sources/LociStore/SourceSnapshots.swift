import Foundation
import GRDB
import LociModel

/// What each source has now (`source_snapshot`, written over on every try) and the numbers it got over
/// time (`source_series`, one row per record per fetch that worked).
extension StoreDatabase {
  /// How long every fetch is kept; older ones are thinned to the last in each hour.
  public static let seriesKeptWhole: Int64 = 7 * 86_400_000

  public func sourceSnapshot(_ source: SourceKey) throws -> SourceSnapshot? {
    try queue.read { db in try Self.snapshot(source, in: db) }
  }

  /// The snapshots of the sources that have one.
  public func sourceSnapshots(_ sources: Set<SourceKey>) throws -> [SourceKey: SourceSnapshot] {
    try queue.read { db in
      var found: [SourceKey: SourceSnapshot] = [:]
      for source in sources {
        if let snapshot = try Self.snapshot(source, in: db) { found[source] = snapshot }
      }
      return found
    }
  }

  /// Keeps what a fetch got: the snapshot is written over and its failures forgotten, each record's numbers are
  /// added to the series, and the entries not kept before are kept. With `watching`, the source's title, what
  /// is new (entries never seen, or records that changed) waits for watch triage, kept in the same write.
  @discardableResult
  public func recordFetch(
    _ source: SourceKey, records: [String: SourceRecord], state: JSONValue?, at moment: Timestamp,
    entries: [SourceEntry] = [], watching title: String? = nil
  ) throws -> SourceSnapshot {
    let snapshot = SourceSnapshot(fetched: moment, records: records, state: state)
    let body = try MirrorUpdate.json(snapshot)
    let rows = try records.sorted { $0.key < $1.key }.compactMap { record, fields -> (String, String)? in
      let numbers = fields.compactMapValues(\.number)
      return numbers.isEmpty ? nil : (record, try MirrorUpdate.json(numbers))
    }
    try queue.write { db in
      let previous = try Self.snapshot(source, in: db)
      let fresh = try Self.recordEntries(source, entries, at: moment, in: db)
      if let title, !fresh.isEmpty || previous?.records != records {
        try Self.keepWatchBatch(
          WatchBatch(source: source, title: title, entries: fresh, previous: previous, snapshot: snapshot), in: db)
      }
      try Self.put(source, body, in: db)
      for (record, numbers) in rows {
        try db.execute(
          sql: "INSERT INTO source_series (source, record, at, body) VALUES (?, ?, ?, ?)",
          arguments: [source.description, record, moment.description, numbers])
      }
      try Self.thin(source, before: moment.millisecondsSince1970 - Self.seriesKeptWhole, in: db)
    }
    return snapshot
  }

  /// Notes a try that got nothing: the records stay as they were, and the snapshot is stale; `script` when
  /// its script failed, which counts toward its being broken. `nil` when the source never got anything.
  @discardableResult
  public func recordFailure(_ source: SourceKey, script: SourceProblems? = nil, at moment: Timestamp) throws
    -> SourceSnapshot?
  {
    try queue.write { db in
      guard let failed = try Self.snapshot(source, in: db)?.failed(at: moment, script: script) else { return nil }
      try Self.put(source, try MirrorUpdate.json(failed), in: db)
      return failed
    }
  }

  /// A number field's values since `since`, oldest first.
  public func sourceSeries(_ source: SourceKey, field: SourceField, since: Timestamp) throws -> [SourcePoint] {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT at, json_extract(body, '$."' || ? || '"') AS value FROM source_series
          WHERE source = ? AND record = ? AND at >= ? ORDER BY at
          """,
        arguments: [field.field, source.description, field.record, since.description]
      ).compactMap { row in
        guard let at = Timestamp(row["at"] as String), let value = row["value"] as Double? else { return nil }
        return SourcePoint(at: at, value: value)
      }
    }
  }

  private static func snapshot(_ source: SourceKey, in db: Database) throws -> SourceSnapshot? {
    try String.fetchOne(db, sql: "SELECT body FROM source_snapshot WHERE source = ?", arguments: [source.description])
      .flatMap { try? decoded(SourceSnapshot.self, $0) }
  }

  private static func put(_ source: SourceKey, _ body: String, in db: Database) throws {
    try db.execute(
      sql:
        "INSERT INTO source_snapshot (source, body) VALUES (?, ?) ON CONFLICT(source) DO UPDATE SET body = excluded.body",
      arguments: [source.description, body])
  }

  /// Keeps the last row of each record in each hour before `cutoff`.
  private static func thin(_ source: SourceKey, before cutoff: Int64, in db: Database) throws {
    let before = Timestamp(millisecondsSince1970: cutoff).description
    try db.execute(
      sql: """
        DELETE FROM source_series WHERE source = ? AND at < ? AND seq NOT IN (
          SELECT MAX(seq) FROM source_series WHERE source = ? AND at < ? GROUP BY record, substr(at, 1, 13))
        """,
      arguments: [source.description, before, source.description, before])
  }
}
