import Foundation

/// The person's calendars or reminders on this Mac.
public enum PersonalKind: String, Hashable, Sendable {
  case events, reminders
}

/// What macOS has said about reading one kind.
public enum PersonalAccess: Hashable, Sendable {
  case granted
  case denied
  case undetermined
}

public struct CalendarEvent: Hashable, Sendable {
  public let title: String
  public let start: Date
  public let end: Date
  public let allDay: Bool
  public let calendar: String
  public let location: String?
  public let notes: String?

  public init(
    title: String, start: Date, end: Date, allDay: Bool = false, calendar: String, location: String? = nil,
    notes: String? = nil
  ) {
    self.title = title
    self.start = start
    self.end = end
    self.allDay = allDay
    self.calendar = calendar
    self.location = location
    self.notes = notes
  }
}

public struct Reminder: Hashable, Sendable {
  public let title: String
  public let list: String
  public let due: Date?
  public let completed: Bool
  public let notes: String?

  public init(title: String, list: String, due: Date? = nil, completed: Bool = false, notes: String? = nil) {
    self.title = title
    self.list = list
    self.due = due
    self.completed = completed
    self.notes = notes
  }
}

/// The calendars and reminders on this Mac, read only: there is no way here to add, change or remove one.
public protocol PersonalData: Sendable {
  func access(to kind: PersonalKind) async -> PersonalAccess
  /// Asks macOS, which asks the person the first time; whether reading is allowed now.
  func requestAccess(to kind: PersonalKind) async -> Bool
  func calendars() async -> [String]
  /// Events that overlap the interval, earliest first; `calendars` narrows them by name.
  func events(from start: Date, to end: Date, calendars: [String]?) async -> [CalendarEvent]
  func reminderLists() async -> [String]
  /// `lists` narrows them by name; `completed` gives the done ones instead of the open ones.
  func reminders(lists: [String]?, completed: Bool) async -> [Reminder]
}

/// A Mac with no calendars to read, as in previews and most tests.
public struct NoPersonalData: PersonalData {
  public init() {}
  public func access(to kind: PersonalKind) async -> PersonalAccess { .denied }
  public func requestAccess(to kind: PersonalKind) async -> Bool { false }
  public func calendars() async -> [String] { [] }
  public func events(from start: Date, to end: Date, calendars: [String]?) async -> [CalendarEvent] { [] }
  public func reminderLists() async -> [String] { [] }
  public func reminders(lists: [String]?, completed: Bool) async -> [Reminder] { [] }
}
