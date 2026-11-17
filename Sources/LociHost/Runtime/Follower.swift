import LociModel
import LociStore

/// Brings the database up to date with what changed and tells the subscriptions the changes affect.
struct Follower: Sendable {
  let store: Store
  let database: StoreDatabase
  let hub: Hub

  func follow(_ changes: Set<ContentChange>) async {
    let onDisk = changes.filter { !$0.isInMemory }
    if !onDisk.isEmpty {
      do {
        await hub.followed(onDisk, problems: try database.apply(onDisk, from: store))
      } catch {
        await hub.failed(String(describing: error))
      }
    }
    await hub.refresh(changes)
  }
}

extension ContentChange {
  /// Changes to what the host keeps in memory, which leave the files and their mirrors as they were.
  var isInMemory: Bool {
    switch self {
    case .conversation, .answers: true
    case .mentor, .catalog, .lesson, .item, .notes, .everything: false
    }
  }
}
