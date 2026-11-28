import Foundation
import GRDB
import LociModel

/// The entries each source has read (`source_entry`), by id, with when each was first seen: what tells a new
/// entry from one already offered.
extension StoreDatabase {
  /// The most entries kept for a source; the ones seen longest ago go first.
  public static let entriesKept = 500

  /// Keeps the entries not seen before, as seen at `moment`, and gives them back in the order given.
  @discardableResult
  public func recordEntries(_ source: SourceKey, _ entries: [SourceEntry], at moment: Timestamp) throws
    -> [SourceEntry]
  {
    try queue.write { db in try Self.recordEntries(source, entries, at: moment, in: db) }
  }

  static func recordEntries(_ source: SourceKey, _ entries: [SourceEntry], at moment: Timestamp, in db: Database)
    throws -> [SourceEntry]
  {
    guard !entries.isEmpty else { return [] }
    let bodies = try entries.map { ($0, try MirrorUpdate.json($0)) }
    var new: [SourceEntry] = []
    for (entry, body) in bodies {
      try db.execute(
        sql: "INSERT OR IGNORE INTO source_entry (source, id, seen, body) VALUES (?, ?, ?, ?)",
        arguments: [source.description, entry.id, moment.description, body])
      if db.changesCount > 0 { new.append(entry) }
    }
    try db.execute(
      sql: """
        DELETE FROM source_entry WHERE source = ? AND id NOT IN (
          SELECT id FROM source_entry WHERE source = ? ORDER BY seen DESC, rowid DESC LIMIT ?)
        """,
      arguments: [source.description, source.description, Self.entriesKept])
    return new
  }

  /// The entries kept after `seq` in the order they were first read (all when it is `nil`), at most `limit`.
  public func sourceEntries(_ source: SourceKey, after seq: Int64?, limit: Int) throws -> [SeenEntry] {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT rowid AS seq, seen, body FROM source_entry WHERE source = ? AND rowid > ? ORDER BY rowid LIMIT ?",
        arguments: [source.description, seq ?? 0, limit]
      ).compactMap(Self.seenEntry)
    }
  }

  /// The entries kept under these ids, in no order; ids not kept are left out.
  public func sourceEntries(_ source: SourceKey, ids: [String]) throws -> [SeenEntry] {
    guard !ids.isEmpty else { return [] }
    return try queue.read { db in
      let marks = Array(repeating: "?", count: ids.count).joined(separator: ", ")
      return try Row.fetchAll(
        db, sql: "SELECT rowid AS seq, seen, body FROM source_entry WHERE source = ? AND id IN (\(marks))",
        arguments: StatementArguments([source.description] + ids)
      ).compactMap(Self.seenEntry)
    }
  }

  private static func seenEntry(_ row: Row) -> SeenEntry? {
    guard let seen = Timestamp(row["seen"] as String), let entry = try? decoded(SourceEntry.self, row["body"]) else {
      return nil
    }
    return SeenEntry(entry: entry, seen: seen, seq: row["seq"])
  }
}

/// An entry, when its source first read it, and its place among the entries the source read: later ones
/// have a larger `seq`.
public struct SeenEntry: Hashable, Sendable {
  public let entry: SourceEntry
  public let seen: Timestamp
  public let seq: Int64

  public init(entry: SourceEntry, seen: Timestamp, seq: Int64) {
    self.entry = entry
    self.seen = seen
    self.seq = seq
  }
}
