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
  public let createdAt: Timestamp

  public init(
    id: EntityID, name: String, title: String, follow: String, every: Every, destination: Destination,
    paused: Bool = false, createdAt: Timestamp
  ) {
    self.id = id
    self.name = name
    self.title = title
    self.follow = follow
    self.every = every
    self.destination = destination
    self.paused = paused
    self.createdAt = createdAt
  }

  public var ref: ScheduleRef { .schedule(id) }
}

/// What `loci schedule add <name>` reads: a schedule but its name and what the app gives it.
public struct ScheduleDraft: Hashable, Sendable {
  public let title: String
  public let follow: String
  public let every: Every
  public let destination: Destination

  public init(title: String, follow: String, every: Every, destination: Destination) {
    self.title = title
    self.follow = follow
    self.every = every
    self.destination = destination
  }
}

extension ScheduleDraft: Codable {
  private enum CodingKeys: String, CodingKey {
    case title, follow, every, panel
  }

  /// `{"title", "follow", "every": {"every": "day", "at": "21:00"}, "panel"?}`; without a panel, only notes.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    follow = try container.decode(String.self, forKey: .follow)
    every = try container.decode(Every.self, forKey: .every)
    destination = try container.decodeIfPresent(String.self, forKey: .panel).map(Destination.panel) ?? .notes
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encode(follow, forKey: .follow)
    try container.encode(every, forKey: .every)
    if case .panel(let panel) = destination { try container.encode(panel, forKey: .panel) }
  }
}

/// Which schedule: one set with `loci schedule`, or a panel's own refresh, which its file keeps.
public enum ScheduleRef: Hashable, Codable, Sendable {
  case schedule(EntityID)
  case panel(String)

  /// How runs are filed under it: `schedule/<id>` or `panel/<name>`.
  public var key: String {
    switch self {
    case .schedule(let id): "schedule/\(id)"
    case .panel(let name): "panel/\(name)"
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
  /// Where it was set; what came of it is told in the main conversation either way.
  public let conversation: ConversationRef?
  public let createdAt: Timestamp

  public init(id: EntityID, due: Timestamp, what: String, conversation: ConversationRef?, createdAt: Timestamp) {
    self.id = id
    self.due = due
    self.what = what
    self.conversation = conversation
    self.createdAt = createdAt
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

  public init(schedules: [ScheduleEntry], followUps: [FollowUp], next: Timestamp?) {
    self.schedules = schedules
    self.followUps = followUps
    self.next = next
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

  public var id: String { ref.key }

  public init(
    ref: ScheduleRef, name: String, title: String, every: Every, destination: Destination, paused: Bool,
    next: Timestamp?, lastSummary: String?
  ) {
    self.ref = ref
    self.name = name
    self.title = title
    self.every = every
    self.destination = destination
    self.paused = paused
    self.next = next
    self.lastSummary = lastSummary
  }
}
