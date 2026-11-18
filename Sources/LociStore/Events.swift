import Foundation
import GRDB
import LociModel

/// Something that happened in the library, as the log keeps it.
public enum LibraryEvent: Hashable, Codable, Sendable {
  /// The person read the item to the end.
  case finishedReading(EntityID)
  /// The item went into the library.
  case saved(EntityID)
  /// The person marked a passage of the item.
  case highlighted(EntityID, note: EntityID)

  public var item: EntityID {
    switch self {
    case .finishedReading(let item), .saved(let item), .highlighted(let item, _): item
    }
  }
}

/// One line of the log.
public struct LoggedEvent: Hashable, Sendable {
  public let id: EntityID
  public let at: Timestamp
  public let event: LibraryEvent

  public init(id: EntityID, at: Timestamp, event: LibraryEvent) {
    self.id = id
    self.at = at
    self.event = event
  }
}

extension StoreDatabase {
  public func log(_ event: LoggedEvent) throws {
    let body = try MirrorUpdate.json(event.event)
    try queue.write { db in
      try db.execute(
        sql: "INSERT INTO event (id, at, item_id, body) VALUES (?, ?, ?, ?)",
        arguments: [event.id.description, event.at.description, event.event.item.description, body])
    }
  }

  /// What happened after `moment`, or ever, oldest first.
  public func events(after moment: Timestamp? = nil) throws -> [LoggedEvent] {
    try queue.read { db in
      try Row.fetchAll(
        db, sql: "SELECT id, at, body FROM event WHERE at > ? ORDER BY seq",
        arguments: [moment?.description ?? ""]
      ).compactMap { row in
        let id: String = row["id"]
        let at: String = row["at"]
        let body: String = row["body"]
        guard let id = EntityID(canonical: id), let at = Timestamp(at),
          let event = try? JSONDecoder().decode(LibraryEvent.self, from: Data(body.utf8))
        else { return nil }
        return LoggedEvent(id: id, at: at, event: event)
      }
    }
  }

  /// What happened to an item goes with it.
  public func deleteEvents(about item: EntityID) throws {
    try queue.write { db in
      try db.execute(sql: "DELETE FROM event WHERE item_id = ?", arguments: [item.description])
    }
  }
}
