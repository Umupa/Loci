/// Every job that is not done, for the cards in the library.
public struct AllJobs: Subscription {
  public static let name = "jobs"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> [Job] {
    try await handler.jobs()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .job, .item, .everything: true
      case .course, .courseActivity, .notes, .reading, .media, .conversation, .turnEnded, .review, .loci,
        .runtime, .timers, .connectors, .projects, .source, .nextUps:
        false
      }
    }
  }
}

/// One item's job; `nil` once it is done or when there never was one.
public struct ItemJob: Subscription {
  public static let name = "itemJob"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> Job? {
    try await handler.job(of: item)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .job(let id), .item(let id): id == item
      case .everything: true
      case .course, .courseActivity, .notes, .reading, .media, .conversation, .turnEnded, .review, .loci,
        .runtime, .timers, .connectors, .projects, .source, .nextUps:
        false
      }
    }
  }
}

/// What a video or audio item shows beside its player: the transcript as it grows, its translations and
/// its outline.
public struct ItemMedia: Subscription {
  public static let name = "itemMedia"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> MediaPage {
    try await handler.mediaPage(item)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .job(let id), .item(let id): id == item
      case .everything: true
      case .course, .courseActivity, .notes, .reading, .media, .conversation, .turnEnded, .review, .loci,
        .runtime, .timers, .connectors, .projects, .source, .nextUps:
        false
      }
    }
  }
}

/// The media section of the settings, with installs and downloads as they progress.
public struct MediaSettings: Subscription {
  public static let name = "mediaSettings"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> MediaSetup {
    try await handler.mediaSetup()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .media, .everything: true
      case .course, .courseActivity, .item, .notes, .reading, .job, .conversation, .turnEnded, .review, .loci,
        .runtime, .timers, .connectors, .projects, .source, .nextUps:
        false
      }
    }
  }
}
