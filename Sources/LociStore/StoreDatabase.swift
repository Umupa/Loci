import Foundation
import GRDB
import LociModel

/// `loci.sqlite`: mirrors of the files for querying and search, plus state that lives only here.
///
/// The mirrors can always be rebuilt from the files, and the files win whenever the two disagree.
public struct StoreDatabase: Sendable {
  let queue: DatabaseQueue

  private init(_ queue: DatabaseQueue) throws(DatabaseOpenError) {
    self.queue = queue
    do {
      try Schema.prepare(queue)
    } catch let error as DatabaseOpenError {
      throw error
    } catch {
      throw .unreadable(String(describing: error))
    }
  }

  /// Opens the database at `url`, creating it if needed. A database that cannot be used is left as it is.
  public static func open(at url: URL) throws(DatabaseOpenError) -> StoreDatabase {
    let queue: DatabaseQueue
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      queue = try DatabaseQueue(path: url.path(percentEncoded: false))
    } catch {
      throw .unreadable(String(describing: error))
    }
    return try StoreDatabase(queue)
  }

  /// A database that lives only in memory, for tests and previews.
  public static func inMemory() throws(DatabaseOpenError) -> StoreDatabase {
    do {
      return try StoreDatabase(DatabaseQueue())
    } catch let error as DatabaseOpenError {
      throw error
    } catch {
      throw .unreadable(String(describing: error))
    }
  }

  /// Moves an unusable database aside as `<name>.unusable-<milliseconds>` and opens a new, empty one.
  ///
  /// The mirrors come back with the next rebuild; reading positions do not, so the caller must tell the
  /// person. The moved file is returned so it can be recovered by hand.
  public static func replace(at url: URL, now: Timestamp) throws -> (database: StoreDatabase, setAside: URL) {
    let setAside = url.deletingLastPathComponent()
      .appending(path: "\(url.lastPathComponent).unusable-\(now.millisecondsSince1970)")
    try FileManager.default.moveItem(at: url, to: setAside)
    for suffix in ["-wal", "-shm"] {
      let companion = URL(filePath: url.path(percentEncoded: false) + suffix)
      if FileManager.default.fileExists(atPath: companion.path(percentEncoded: false)) {
        try FileManager.default.removeItem(at: companion)
      }
    }
    return (try open(at: url), setAside)
  }
}

/// Why a database could not be opened. Nothing is changed on disk when this is thrown.
public enum DatabaseOpenError: Error, Equatable {
  /// Not a database, damaged, or failing its integrity check.
  case unreadable(String)
  /// Written by a newer Loci: it holds changes to the schema this version does not know.
  case newerVersion(unknownMigrations: [String])
}
