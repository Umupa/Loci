import Foundation

/// Every item, newest first.
public struct AllItems: Subscription {
  public static let name = "items"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> [Item] {
    try await handler.listItems()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .item, .everything: true
      case .course, .courseActivity, .notes, .reading, .job, .media, .conversation, .turnEnded, .review, .loci,
        .runtime, .timers, .connectors, .projects, .source, .nextUps:
        false
      }
    }
  }
}

/// One item with its text.
public struct OneItem: Subscription {
  public static let name = "item"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> ItemPage {
    try await handler.itemPage(item)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .item(let id), .job(let id): id == item
      case .everything: true
      case .course, .courseActivity, .notes, .reading, .media, .conversation, .turnEnded, .review, .loci,
        .runtime, .timers, .connectors, .projects, .source, .nextUps:
        false
      }
    }
  }
}

/// Whether storage is sound, and the files that could not be used.
public struct HealthReport: Subscription {
  public static let name = "health"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> Health {
    await handler.health()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    true
  }
}

public struct ItemCover: Subscription {
  public static let name = "itemCover"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> Data? {
    try await handler.cover(of: item)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.item(item)) || changes.contains(.everything)
  }
}
