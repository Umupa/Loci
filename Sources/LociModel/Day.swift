import Foundation

/// A calendar day in the host's time zone, written `2026-11-18`.
public struct Day: Hashable, Comparable, Sendable, TextCodable {
  public let year: Int
  public let month: Int
  public let day: Int

  /// `nil` for a day the Gregorian calendar does not have, such as February 30.
  public init?(year: Int, month: Int, day: Int) {
    let components = DateComponents(year: year, month: month, day: day)
    guard (1...9999).contains(year), components.isValidDate(in: Self.calendar(in: .gmt)) else { return nil }
    self.year = year
    self.month = month
    self.day = day
  }

  /// The day `moment` falls on in `timeZone`.
  public init(containing moment: Timestamp, in timeZone: TimeZone) {
    let parts = Self.calendar(in: timeZone).dateComponents([.year, .month, .day], from: moment.date)
    year = parts.year ?? 1970
    month = parts.month ?? 1
    day = parts.day ?? 1
  }

  public init?(_ description: String) {
    guard let match = description.wholeMatch(of: /(\d{4})-(\d\d)-(\d\d)/),
      let year = Int(match.1), let month = Int(match.2), let day = Int(match.3)
    else { return nil }
    self.init(year: year, month: month, day: day)
  }

  public var description: String {
    "\(String(year).leftPadded(to: 4))-\(String(month).leftPadded(to: 2))-\(String(day).leftPadded(to: 2))"
  }

  /// The first moment of the day in `timeZone`.
  public func start(in timeZone: TimeZone) -> Timestamp {
    let calendar = Self.calendar(in: timeZone)
    let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    return Timestamp(calendar.startOfDay(for: date))
  }

  /// The day `count` days later, or earlier for a negative count.
  public func adding(days count: Int) -> Day {
    let calendar = Self.calendar(in: .gmt)
    let moved = calendar.date(byAdding: .day, value: count, to: start(in: .gmt).date) ?? start(in: .gmt).date
    return Day(containing: Timestamp(moved), in: .gmt)
  }

  /// Whole days from this day to `later`, counting neither end.
  public func days(until later: Day) -> Int {
    Self.calendar(in: .gmt).dateComponents([.day], from: start(in: .gmt).date, to: later.start(in: .gmt).date).day
      ?? 0
  }

  public static func < (lhs: Day, rhs: Day) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  private static func calendar(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }
}

/// Hours and minutes on a 24-hour clock, written `09:12`.
public struct TimeOfDay: Hashable, Comparable, Sendable, TextCodable {
  public let hour: Int
  public let minute: Int

  public init?(hour: Int, minute: Int) {
    guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
    self.hour = hour
    self.minute = minute
  }

  /// The time `moment` shows on a clock in `timeZone`.
  public init(of moment: Timestamp, in timeZone: TimeZone) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.hour, .minute], from: moment.date)
    hour = parts.hour ?? 0
    minute = parts.minute ?? 0
  }

  /// `9:12` is read as `09:12`.
  public init?(_ description: String) {
    guard let match = description.wholeMatch(of: /(\d{1,2}):(\d\d)/), let hour = Int(match.1),
      let minute = Int(match.2)
    else { return nil }
    self.init(hour: hour, minute: minute)
  }

  public var description: String {
    "\(String(hour).leftPadded(to: 2)):\(String(minute).leftPadded(to: 2))"
  }

  public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
    (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
  }
}
