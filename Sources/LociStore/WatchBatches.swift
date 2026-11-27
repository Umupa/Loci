import Foundation
import GRDB
import LociModel

/// What one fetch of a source brought that is new, waiting for watch triage (`watch_batch`): kept in the write
/// that keeps the fetch, and gone once triage decided on it, so neither a restart nor a missing model loses one.
public struct WatchBatch: Codable, Sendable {
  public let source: SourceKey
  /// The source's title, which findings name as where they came from.
  public let title: String
  /// The entries the source never had before.
  public let entries: [SourceEntry]
  /// The snapshot before this fetch; `nil` for the first.
  public let previous: SourceSnapshot?
  public let snapshot: SourceSnapshot
}

public struct WaitingWatchBatch: Sendable {
  public let id: Int64
  public let batch: WatchBatch
  /// Answers of the model the app could not read, which give the batch up after a few.
  public let tries: Int
  /// Calls to the model that failed in a row, which are tried again as long as it takes.
  public let failures: Int
  /// Why the last try failed, and when; `nil` before any failed.
  public let problem: String?
  public let tried: Timestamp?
  /// When the next try may start, after one failed.
  public let notBefore: Timestamp?
}

extension StoreDatabase {
  /// Every batch waiting, oldest first.
  public func waitingWatchBatches() throws -> [WaitingWatchBatch] {
    try queue.read { db in
      try Row.fetchAll(
        db, sql: "SELECT id, body, tries, failures, problem, tried, not_before FROM watch_batch ORDER BY id"
      ).map { row in
        try WaitingWatchBatch(
          id: row["id"], batch: Self.decoded(WatchBatch.self, row["body"]), tries: row["tries"],
          failures: row["failures"], problem: row["problem"], tried: (row["tried"] as String?).flatMap(Timestamp.init),
          notBefore: (row["not_before"] as String?).flatMap(Timestamp.init))
      }
    }
  }

  static func keepWatchBatch(_ batch: WatchBatch, in db: Database) throws {
    try db.execute(
      sql: "INSERT INTO watch_batch (source, body) VALUES (?, ?)",
      arguments: [batch.source.description, try MirrorUpdate.json(batch)])
  }

  public func finishWatchBatch(_ id: Int64) throws {
    try queue.write { db in try db.execute(sql: "DELETE FROM watch_batch WHERE id = ?", arguments: [id]) }
  }

  /// Notes an answer the app could not read; it counts toward giving the batch up.
  public func retryWatchBatch(_ id: Int64, problem: String, at now: Timestamp, notBefore: Timestamp) throws {
    try queue.write { db in
      try db.execute(
        sql: "UPDATE watch_batch SET tries = tries + 1, problem = ?, tried = ?, not_before = ? WHERE id = ?",
        arguments: [problem, now.description, notBefore.description, id])
    }
  }

  /// Notes a call to the model that failed; the batch waits and is tried again, however often it fails.
  public func failWatchBatch(_ id: Int64, problem: String, at now: Timestamp, notBefore: Timestamp) throws {
    try queue.write { db in
      try db.execute(
        sql: "UPDATE watch_batch SET failures = failures + 1, problem = ?, tried = ?, not_before = ? WHERE id = ?",
        arguments: [problem, now.description, notBefore.description, id])
    }
  }

  /// Lets every batch waiting to be tried again be tried at once, as when the model services change.
  public func retryWatchBatchesNow() throws {
    try queue.write { db in try db.execute(sql: "UPDATE watch_batch SET not_before = NULL") }
  }

  /// The home's latest watch findings, newest first, for triage to know an event it already raised.
  public func recentWatchFindings(in home: Home, limit: Int) throws -> [WatchFinding] {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT body FROM inbox WHERE key GLOB ? ORDER BY seq DESC LIMIT ?",
        arguments: [home.folder + "watch/*", limit]
      ).compactMap { body in
        guard case .watch(let finding, _)? = (try? Self.decoded(Event.self, body))?.source else { return nil }
        return finding
      }
    }
  }
}
