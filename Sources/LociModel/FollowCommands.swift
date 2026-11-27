import Foundation

/// Reads what a followable link leads to, for the follow card. Refused when the link cannot be followed or read.
public struct PreviewFollow: RemoteCommand {
  public static let name = "follows.preview"
  public let link: URL

  public init(_ link: URL) {
    self.link = link
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> FollowPreview {
    try await handler.previewFollow(self)
  }
}

/// Follows the channel or show behind a link; the follow it already is when it is one. The episodes out by now
/// are not new.
public struct StartFollowing: RemoteCommand {
  public static let name = "follows.start"
  public let link: URL

  public init(_ link: URL) {
    self.link = link
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Follow {
    try await handler.startFollowing(self)
  }
}

/// The companion follows a channel or show for the person with `loci follow`, as `StartFollowing` does.
public struct AddFollow: LocalToolCommand {
  public static let name = "follows.add"
  public let link: URL

  public init(_ link: URL) {
    self.link = link
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Follow {
    try await handler.startFollowing(StartFollowing(link))
  }
}

/// Stops following, and gives the follow that was, for `RestoreFollowing`. The items taken in from it stay.
public struct StopFollowing: RemoteCommand {
  public static let name = "follows.stop"
  public let follow: EntityID

  public init(_ follow: EntityID) {
    self.follow = follow
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Follow {
    try await handler.stopFollowing(self)
  }
}

/// Follows again what `StopFollowing` stopped, as it was.
public struct RestoreFollowing: RemoteCommand {
  public static let name = "follows.restore"
  public let follow: Follow

  public init(_ follow: Follow) {
    self.follow = follow
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.restoreFollowing(self)
  }
}

/// The person opened the follow page: what came out until now is no longer new.
public struct SawFollow: RemoteCommand {
  public static let name = "follows.saw"
  public let follow: EntityID

  public init(_ follow: EntityID) {
    self.follow = follow
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.sawFollow(self)
  }
}

/// Reads a follow's episodes again, its past ones too; the follow page asks when it opens and when the person
/// tries again.
public struct RefreshFollow: RemoteCommand {
  public static let name = "follows.refresh"
  public let follow: EntityID
  /// Lists the past episodes even when they were listed within the hour.
  public let again: Bool

  public init(_ follow: EntityID, again: Bool = false) {
    self.follow = follow
    self.again = again
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.refreshFollow(self)
  }
}

/// Where an item came from, when that channel or show can be followed; `nil` when it cannot.
public struct FollowOfItem: RemoteCommand {
  public static let name = "follows.ofItem"
  public let item: EntityID

  public init(_ item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> ItemFollow? {
    try await handler.followOfItem(self)
  }
}

/// Every follow with its newest episode and the episodes taken into the library, for `loci follow list`.
public struct ListFollows: LocalToolCommand {
  public static let name = "follows.list"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> [FollowListing] {
    try await handler.listFollows()
  }
}

/// Every follow, the most recently updated first.
public struct AllFollows: Subscription {
  public static let name = "follows.all"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> [FollowSummary] {
    try await handler.followSummaries()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .follows, .everything: true
      case .item, .course, .courseActivity, .notes, .reading, .job, .media, .conversation, .turnEnded, .review, .loci,
        .runtime, .agentModels, .timers, .connectors, .projects, .source, .nextUps:
        false
      }
    }
  }
}

/// One follow page; `nil` once it is no longer followed.
public struct OneFollow: Subscription {
  public static let name = "follows.one"
  public let follow: EntityID

  public init(_ follow: EntityID) {
    self.follow = follow
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> FollowPage? {
    try await handler.followPage(follow)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .follows, .item, .everything: true
      case .course, .courseActivity, .notes, .reading, .job, .media, .conversation, .turnEnded, .review, .loci,
        .runtime, .agentModels, .timers, .connectors, .projects, .source, .nextUps:
        false
      }
    }
  }
}
