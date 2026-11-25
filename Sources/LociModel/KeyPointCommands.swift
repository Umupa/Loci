/// Starts picking an item's key points with `choice`, replacing any picked before, and remembers the choice
/// for next time. Returns at once; `ItemKeyPoints` shows the picking and then the key points.
public struct PickKeyPoints: RemoteCommand {
  public static let name = "library.pickKeyPoints"
  public let item: EntityID
  public let choice: KeyPointChoice

  public init(item: EntityID, choice: KeyPointChoice) {
    self.item = item
    self.choice = choice
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.pickKeyPoints(self)
  }
}

/// An item's key points, whether they are being picked, and the choice picking starts with.
public struct ItemKeyPoints: Subscription {
  public static let name = "itemKeyPoints"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> KeyPointsPage {
    try await handler.keyPointsPage(item)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .item(let id): id == item
      case .everything: true
      case .course, .courseActivity, .job, .notes, .reading, .media, .conversation, .turnEnded, .review, .loci,
        .runtime, .timers, .connectors, .projects, .source:
        false
      }
    }
  }
}
