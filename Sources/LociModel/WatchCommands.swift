/// A home's `WATCH.md` as it is now, kept current as the companion and the person change it.
public struct WatchNotes: Subscription {
  public static let name = "watch.notes"
  public let project: Project.ID?

  public init(of home: Home) {
    project = home.project
  }

  public var home: Home { Home(project) }

  public func value(from handler: any CommandHandler) async throws(HostError) -> String {
    try await handler.watch(of: home)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.loci(.watch)) || changes.contains(.everything)
  }
}

/// Writes a home's `WATCH.md` whole; the next batch of watch triage reads it. `notFound` for a project that
/// is gone.
public struct SaveWatch: RemoteCommand {
  public static let name = "watch.save"
  public let project: Project.ID?
  public let text: String

  public init(_ text: String, in home: Home) {
    project = home.project
    self.text = text
  }

  public var home: Home { Home(project) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.saveWatch(self)
  }
}
