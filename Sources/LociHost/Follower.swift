import LociModel
import LociStore

/// Brings the database up to date with what changed and tells the subscriptions the changes affect.
struct Follower: Sendable {
  let store: Store
  let database: StoreDatabase
  let hub: Hub

  func follow(_ changes: Set<ContentChange>) async {
    let onDisk = changes.filter { !$0.leavesMirrorsAlone }
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
  /// Changes that leave the database's mirrors as they were: what the host keeps in memory, and files that
  /// are read afresh each time.
  var leavesMirrorsAlone: Bool {
    switch self {
    case .reading, .job, .media, .conversation, .turnEnded, .review, .loci, .runtime, .timers: true
    case .courseActivity: true
    case .item, .notes, .course, .everything: false
    }
  }
}
