import Foundation

/// How often a schedule comes due: an hour after the last run, or at a time of day, or of the week. A time
/// that passed while the app was closed or the Mac slept is due once, however many were missed.
public enum Every: Hashable, Sendable {
  case hour
  case day(at: TimeOfDay)
  case week(Weekday, at: TimeOfDay)

  static let hourMilliseconds: Int64 = 60 * 60 * 1000

  /// A panel's `refresh`, read as a schedule; `nil` when it lacks the time or the day it needs.
  public init?(_ refresh: PanelRefresh) {
    switch refresh.every {
    case .hour: self = .hour
    case .day:
      guard let at = refresh.at.flatMap(TimeOfDay.init) else { return nil }
      self = .day(at: at)
    case .week:
      guard let at = refresh.at.flatMap(TimeOfDay.init), let day = refresh.weekday.flatMap(Weekday.init) else {
        return nil
      }
      self = .week(day, at: at)
    }
  }

  /// The same, as a panel file and `loci schedule` write it.
  public var refresh: PanelRefresh {
    switch self {
    case .hour: PanelRefresh(every: .hour)
    case .day(let at): PanelRefresh(every: .day, at: at.description)
    case .week(let day, let at): PanelRefresh(every: .week, at: at.description, weekday: day.rawValue)
    }
  }

  /// The moment it came due at, when it is due at `now` and last ran at `last`; `nil` when it is not due.
  /// Never having run, it is due at once.
  public func due(last: Timestamp?, now: Timestamp, in timeZone: TimeZone) -> Timestamp? {
    guard let last else { return now }
    switch self {
    case .hour:
      let due = Timestamp(millisecondsSince1970: last.millisecondsSince1970 + Self.hourMilliseconds)
      return due <= now ? due : nil
    case .day, .week:
      guard let mark = latest(atOrBefore: now, in: timeZone), last < mark else { return nil }
      return mark
    }
  }

  /// When it is due next: `now` when it is due already.
  public func next(last: Timestamp?, now: Timestamp, in timeZone: TimeZone) -> Timestamp {
    if due(last: last, now: now, in: timeZone) != nil { return now }
    switch self {
    case .hour:
      return Timestamp(millisecondsSince1970: (last ?? now).millisecondsSince1970 + Self.hourMilliseconds)
    case .day, .week:
      let today = Day(containing: now, in: timeZone)
      for days in 0...8 {
        let day = today.adding(days: days)
        if let moment = moment(on: day, in: timeZone), moment > now { return moment }
      }
      return now
    }
  }

  /// The last moment up to `now` it was meant to come due at; `nil` for `hour`, which follows the last run.
  public func latest(atOrBefore now: Timestamp, in timeZone: TimeZone) -> Timestamp? {
    let today = Day(containing: now, in: timeZone)
    for days in 0...7 {
      if let moment = moment(on: today.adding(days: -days), in: timeZone), moment <= now { return moment }
    }
    return nil
  }

  /// The moment on `day` it comes due at, if it comes due that day.
  private func moment(on day: Day, in timeZone: TimeZone) -> Timestamp? {
    let at: TimeOfDay
    switch self {
    case .hour: return nil
    case .day(let time): at = time
    case .week(let weekday, let time):
      guard Weekday(of: day, in: timeZone) == weekday else { return nil }
      at = time
    }
    return Timestamp(
      millisecondsSince1970: day.start(in: timeZone).millisecondsSince1970 + Int64(at.hour * 60 + at.minute) * 60_000)
  }
}

extension Every: Codable {
  public init(from decoder: any Decoder) throws {
    let refresh = try PanelRefresh(from: decoder)
    guard let every = Every(refresh) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "day needs \"at\"; week needs \"weekday\" and \"at\""))
    }
    self = every
  }

  public func encode(to encoder: any Encoder) throws {
    try refresh.encode(to: encoder)
  }
}

/// A day of the week, numbered as `Calendar` numbers them: 1 is Sunday.
public enum Weekday: Int, Hashable, Codable, Sendable, CaseIterable {
  case sunday = 1
  case monday, tuesday, wednesday, thursday, friday, saturday

  public init(of day: Day, in timeZone: TimeZone) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    self = Weekday(rawValue: calendar.component(.weekday, from: day.start(in: timeZone).date)) ?? .sunday
  }

  /// `monday`, `mon`, case aside.
  public init?(name: String) {
    let name = name.lowercased()
    guard name.count >= 3, let day = Self.allCases.first(where: { "\($0)".hasPrefix(name) }) else { return nil }
    self = day
  }
}
