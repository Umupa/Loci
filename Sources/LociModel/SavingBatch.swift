/// What Loci is putting into the library with `loci save`: everything it saved while any of it was still
/// waiting its turn or being worked on. The batch ends once none of it is; Loci's next save starts another.
public struct SavingBatch: Hashable, Codable, Sendable {
  /// In the order Loci saved them.
  public let items: [EntityID]
  /// How many of `items` no longer have work going on: done, failed, paused, waiting for the reader or deleted.
  public let finished: Int

  public init(items: [EntityID], finished: Int) {
    self.items = items
    self.finished = finished
  }
}

/// The batch Loci is saving now; `nil` while it saves nothing.
public struct SavingNow: Subscription {
  public static let name = "jobs.saving"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> SavingBatch? {
    await handler.savingBatch()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .job, .item, .everything: true
      case .course, .courseActivity, .notes, .reading, .media, .conversation, .turnEnded, .review, .loci,
        .runtime, .timers, .connectors:
        false
      }
    }
  }
}

/// Deletes the items of the batch Loci is saving whose work has not started yet, as `DeleteItems` does, so
/// `RestoreDeleted` brings them back. Replies with how many were deleted.
public struct StopSaving: RemoteCommand {
  public static let name = "jobs.stopSaving"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> Int {
    try await handler.stopSaving()
  }
}
