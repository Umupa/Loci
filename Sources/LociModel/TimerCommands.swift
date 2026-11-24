/// The schedules, panels' refreshes among them, and the follow-ups still to come due.
public struct WatchTimers: Subscription {
  public static let name = "loci.timers"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> Timers {
    try await handler.timers()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.timers) || changes.contains(.loci(.panels)) || changes.contains(.everything)
  }
}

/// A schedule's latest runs, newest first.
public struct WatchScheduleRuns: Subscription {
  public static let name = "loci.scheduleRuns"
  public let schedule: ScheduleRef
  public let limit: Int

  public init(_ schedule: ScheduleRef, limit: Int = 10) {
    self.schedule = schedule
    self.limit = limit
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> [Run] {
    try await handler.runs(of: schedule, limit: limit)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.timers) || changes.contains(.everything)
  }
}

public struct ListTimers: RemoteCommand {
  public static let name = "timers.list"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> Timers {
    try await handler.timers()
  }
}

/// Stops a schedule coming due, or lets it again; a paused one missed nothing when it goes on.
public struct PauseSchedule: RemoteCommand {
  public static let name = "timers.pause"
  public let schedule: ScheduleRef
  public let paused: Bool

  public init(_ schedule: ScheduleRef, paused: Bool) {
    self.schedule = schedule
    self.paused = paused
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.pauseSchedule(self)
  }
}

/// Changes how often a schedule comes due; a panel's refresh is changed in the panel's file.
public struct ChangeScheduleEvery: RemoteCommand {
  public static let name = "timers.changeEvery"
  public let schedule: ScheduleRef
  public let every: Every

  public init(_ schedule: ScheduleRef, every: Every) {
    self.schedule = schedule
    self.every = every
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> ScheduleEntry {
    try await handler.changeScheduleEvery(self)
  }
}

/// Deletes a schedule. For a panel's refresh, the panel stays and is no longer refreshed.
public struct RemoveSchedule: RemoteCommand {
  public static let name = "timers.removeSchedule"
  public let schedule: ScheduleRef

  public init(_ schedule: ScheduleRef) {
    self.schedule = schedule
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.removeSchedule(self)
  }
}

/// Adds a schedule, first due at its next time. Refused when the name is taken or not a name, or the panel
/// it goes to is not there.
public struct AddSchedule: LocalToolCommand {
  public static let name = "timers.addSchedule"
  public let scheduleName: String
  public let draft: ScheduleDraft

  public init(_ name: String, _ draft: ScheduleDraft) {
    scheduleName = name
    self.draft = draft
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> ScheduleEntry {
    try await handler.addSchedule(self)
  }
}

/// Adds a follow-up. Refused when the moment has passed.
public struct AddFollowUp: LocalToolCommand {
  public static let name = "timers.addFollowUp"
  public let time: FollowUpTime
  public let what: String
  /// Where it was set; the app fills it in from the session the command came from.
  public let conversation: ConversationRef?

  public init(_ time: FollowUpTime, _ what: String, in conversation: ConversationRef? = nil) {
    self.time = time
    self.what = what
    self.conversation = conversation
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> FollowUp {
    try await handler.addFollowUp(self)
  }
}

/// Cancels a follow-up before it comes due.
public struct CancelFollowUp: RemoteCommand {
  public static let name = "timers.cancelFollowUp"
  public let followUp: EntityID

  public init(_ followUp: EntityID) {
    self.followUp = followUp
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.cancelFollowUp(self)
  }
}
