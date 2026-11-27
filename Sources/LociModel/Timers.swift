import Foundation

/// Where what a schedule's run finds goes: a panel it keeps current, or only today's notes.
public enum Destination: Hashable, Codable, Sendable {
  case panel(String)
  case notes
}

/// A timer that comes due again and again, which the companion set in a conversation.
public struct Schedule: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  /// Short lowercase English, as panels are named, and unique among schedules: `cubesandbox-news`.
  public let name: String
  /// In the person's language, as the Timers page shows it.
  public let title: String
  /// What to look at each time, in the person's words.
  public let follow: String
  public let every: Every
  public let destination: Destination
  public let paused: Bool
  /// How long after each time it comes due its event stays worth doing.
  public let deadlineMinutes: Int?
  public let createdAt: Timestamp
  /// The project it was set in; `nil` for the chat's. Its panel is that project's.
  public let project: Project.ID?

  public init(
    id: EntityID, name: String, title: String, follow: String, every: Every, destination: Destination,
    paused: Bool = false, createdAt: Timestamp, in home: Home, deadlineMinutes: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.title = title
    self.follow = follow
    self.every = every
    self.destination = destination
    self.paused = paused
    self.deadlineMinutes = deadlineMinutes
    self.createdAt = createdAt
    project = home.project
  }

  public func deadline(for due: Timestamp) -> Timestamp? {
    deadlineMinutes.map { Timestamp(millisecondsSince1970: due.millisecondsSince1970 + Int64($0) * 60_000) }
  }

  public var ref: ScheduleRef { .schedule(id) }
  public var home: Home { Home(project) }
}

/// What `loci schedule add <name>` reads: a schedule but its name and what the app gives it.
public struct ScheduleDraft: Hashable, Sendable {
  public let title: String
  public let follow: String
  public let every: Every
  public let destination: Destination
  public let deadlineMinutes: Int?

  public init(title: String, follow: String, every: Every, destination: Destination, deadlineMinutes: Int? = nil) {
    self.title = title
    self.follow = follow
    self.every = every
    self.destination = destination
    self.deadlineMinutes = deadlineMinutes
  }
}

extension ScheduleDraft: Codable {
  private enum CodingKeys: String, CodingKey {
    case title, follow, every, panel, deadlineMinutes
  }

  /// `{"title", "follow", "every": {"every": "day", "at": "21:00"}, "panel"?}`; without a panel, only notes.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    follow = try container.decode(String.self, forKey: .follow)
    every = try container.decode(Every.self, forKey: .every)
    deadlineMinutes = try container.decodeIfPresent(Int.self, forKey: .deadlineMinutes)
    destination = try container.decodeIfPresent(String.self, forKey: .panel).map(Destination.panel) ?? .notes
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encode(follow, forKey: .follow)
    try container.encode(every, forKey: .every)
    try container.encodeIfPresent(deadlineMinutes, forKey: .deadlineMinutes)
    if case .panel(let panel) = destination { try container.encode(panel, forKey: .panel) }
  }
}

/// What `loci schedule change <name>` reads: the fields of `ScheduleDraft` to change, each left out to keep
/// it. `"panel": null` sends what it finds only to the notes.
public struct ScheduleChange: Hashable, Sendable {
  public let title: String?
  public let follow: String?
  public let every: Every?
  public let destination: Destination?

  public init(title: String? = nil, follow: String? = nil, every: Every? = nil, destination: Destination? = nil) {
    self.title = title
    self.follow = follow
    self.every = every
    self.destination = destination
  }

  public var isEmpty: Bool { title == nil && follow == nil && every == nil && destination == nil }
}

extension ScheduleChange: Codable {
  private enum CodingKeys: String, CodingKey {
    case title, follow, every, panel
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    follow = try container.decodeIfPresent(String.self, forKey: .follow)
    every = try container.decodeIfPresent(Every.self, forKey: .every)
    if !container.contains(.panel) {
      destination = nil
    } else if try container.decodeNil(forKey: .panel) {
      destination = .notes
    } else {
      destination = .panel(try container.decode(String.self, forKey: .panel))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(title, forKey: .title)
    try container.encodeIfPresent(follow, forKey: .follow)
    try container.encodeIfPresent(every, forKey: .every)
    switch destination {
    case .panel(let name)?: try container.encode(name, forKey: .panel)
    case .notes?: try container.encodeNil(forKey: .panel)
    case nil: break
    }
  }
}

/// Which schedule: one set with `loci schedule`, or a panel's own refresh, which its file keeps.
public enum ScheduleRef: Hashable, Codable, Sendable {
  case schedule(EntityID)
  /// A panel's refresh; the project is `nil` for a panel of the chat.
  case panel(String, project: Project.ID?)

  public static func panel(_ panel: PanelRef) -> ScheduleRef {
    .panel(panel.name, project: panel.home.project)
  }

  /// How runs are filed under it: `schedule/<id>`, `panel/<name>`, or `projects/<id>/panel/<name>`.
  public var key: String {
    switch self {
    case .schedule(let id): "schedule/\(id)"
    case .panel(let name, let project): Home(project).folder + "panel/\(name)"
    }
  }
}

/// A timer the companion set for itself to come due once, for something it promised to look at again.
/// It leaves the list once it comes due or is cancelled.
public struct FollowUp: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let due: Timestamp
  /// The promise, as the companion wrote it.
  public let what: String
  /// Where it was set; what came of it is told in the main conversation, or in the project's when it was set in one.
  public let conversation: ConversationRef?
  public let createdAt: Timestamp
  /// For one a run set, the run's event; its own event is one level deeper (`Event.depth`).
  public let parent: EntityID?
  public let depth: Int?
  /// Its event's deadline: the parent's unless an earlier one was given.
  public let deadline: Timestamp?
  /// For one a run set, the same for the same words from the same event: setting it again keeps the first.
  public let key: String?

  /// The project it was set in, where its run works and what came of it is told.
  public var home: Home { conversation?.home ?? .chat }

  public init(
    id: EntityID, due: Timestamp, what: String, conversation: ConversationRef?, createdAt: Timestamp,
    parent: EntityID? = nil, depth: Int? = nil, deadline: Timestamp? = nil, key: String? = nil
  ) {
    self.id = id
    self.due = due
    self.what = what
    self.conversation = conversation
    self.createdAt = createdAt
    self.parent = parent
    self.depth = depth
    self.deadline = deadline
    self.key = key
  }
}

/// When a follow-up comes due, as `loci followup` is told it; the host reads it in its own time zone.
public enum FollowUpTime: Hashable, Codable, Sendable {
  /// A day and time; a day with no time is 09:00.
  case at(Day, TimeOfDay?)
  /// The next time the clock shows this, today or tomorrow.
  case next(TimeOfDay)
  case after(minutes: Int)

  public func moment(now: Timestamp, in timeZone: TimeZone) -> Timestamp {
    func on(_ day: Day, _ time: TimeOfDay?) -> Timestamp {
      let minutes = time.map { $0.hour * 60 + $0.minute } ?? 9 * 60
      return Timestamp(millisecondsSince1970: day.start(in: timeZone).millisecondsSince1970 + Int64(minutes) * 60_000)
    }
    switch self {
    case .at(let day, let time): return on(day, time)
    case .next(let time):
      let today = on(Day(containing: now, in: timeZone), time)
      return today > now ? today : on(Day(containing: now, in: timeZone).adding(days: 1), time)
    case .after(let minutes):
      return Timestamp(millisecondsSince1970: now.millisecondsSince1970 + Int64(minutes) * 60_000)
    }
  }
}

/// The Timers page: schedules, panels' refreshes among them, and the follow-ups still to come due.
public struct Timers: Hashable, Codable, Sendable {
  public let schedules: [ScheduleEntry]
  /// Soonest first.
  public let followUps: [FollowUp]
  /// When the next timer comes due; `nil` when none will.
  public let next: Timestamp?
  /// The sources whose new entries and numbers watch triage failed to sort more than once in a row; `nil` from
  /// an older Mac.
  public let triage: [TriageTrouble]?

  public init(schedules: [ScheduleEntry], followUps: [FollowUp], next: Timestamp?, triage: [TriageTrouble] = []) {
    self.schedules = schedules
    self.followUps = followUps
    self.next = next
    self.triage = triage
  }
}

/// A source whose oldest waiting batch watch triage keeps failing to sort: why it failed last, and when.
public struct TriageTrouble: Hashable, Codable, Sendable, Identifiable {
  public let source: SourceKey
  public let title: String
  public let problem: String
  public let tried: Timestamp
  /// Tries that failed in a row.
  public let failed: Int

  public var id: String { source.description }

  public init(source: SourceKey, title: String, problem: String, tried: Timestamp, failed: Int) {
    self.source = source
    self.title = title
    self.problem = problem
    self.tried = tried
    self.failed = failed
  }
}

/// One line of the schedules.
public struct ScheduleEntry: Hashable, Codable, Sendable, Identifiable {
  public let ref: ScheduleRef
  /// For a schedule its name; for a panel's refresh the panel's.
  public let name: String
  public let title: String
  public let every: Every
  /// A panel's own refresh goes to that panel.
  public let destination: Destination
  public let paused: Bool
  /// `nil` while paused.
  public let next: Timestamp?
  /// The last sentence of its last run that finished.
  public let lastSummary: String?
  /// When that run started; `nil` from an older Mac, or before any run finished.
  public let lastRun: Timestamp?
  /// Its market's trading calendar does not reach its next run, which goes by weekdays; `nil` from an older Mac
  /// or for one that follows no market.
  public let calendarUncovered: Bool?

  public var id: String { ref.key }

  public init(
    ref: ScheduleRef, name: String, title: String, every: Every, destination: Destination, paused: Bool,
    next: Timestamp?, lastSummary: String?, lastRun: Timestamp? = nil, calendarUncovered: Bool? = nil
  ) {
    self.ref = ref
    self.name = name
    self.title = title
    self.every = every
    self.destination = destination
    self.paused = paused
    self.next = next
    self.lastSummary = lastSummary
    self.lastRun = lastRun
    self.calendarUncovered = calendarUncovered
  }
}
