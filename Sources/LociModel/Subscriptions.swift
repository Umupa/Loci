/// Every mentor, by name.
public struct AllMentors: Subscription {
  public static let name = "mentors"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> [Mentor] {
    try await handler.listMentors()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .mentor, .everything: true
      case .catalog, .lesson, .item, .notes, .conversation, .mind, .reading: false
      }
    }
  }
}

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
      case .mentor, .catalog, .lesson, .notes, .conversation, .mind, .reading: false
      }
    }
  }
}

/// One mentor with its catalog.
public struct OneMentor: Subscription {
  public static let name = "mentor"
  public let mentor: EntityID

  public init(mentor: EntityID) {
    self.mentor = mentor
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> MentorPage {
    try await handler.mentorPage(mentor)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .mentor(let id), .catalog(let id): id == mentor
      case .lesson(let lesson): lesson.mentor == mentor
      case .reading(.lesson(let lesson)): lesson.mentor == mentor
      case .everything: true
      case .item, .notes, .conversation, .mind, .reading: false
      }
    }
  }
}

/// One item with its text and the lessons that cite it.
public struct OneItem: Subscription {
  public static let name = "item"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> ItemPage {
    try await handler.itemPage(item)
  }

  /// Any mentor or lesson may start or stop citing the item, or rename itself.
  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .item(let id): id == item
      case .mentor, .catalog, .lesson, .everything: true
      case .notes, .conversation, .mind, .reading: false
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
