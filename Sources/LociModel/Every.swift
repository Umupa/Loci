import Foundation

/// How often a schedule comes due: an hour after the last run, at a time of day or of the week, every few
/// minutes within hours of the day, at a time on a market's trading days, or once. A time that passed while the
/// app was closed or the Mac slept is due once, however many were missed. A market's times are in its own time
/// zone, and its days are those its exchange trades on.
public enum Every: Hashable, Sendable {
  case hour
  case day(at: TimeOfDay)
  case week(Weekday, at: TimeOfDay)
  case interval(SourceEvery, SourceWindow, market: Market?)
  case tradingDay(Market, at: TimeOfDay)
  case once(Timestamp)

  /// A panel's `refresh`, read as a schedule; `nil` when it lacks the time, the day, the hours or the market it
  /// needs.
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
    case .interval:
      guard let from = refresh.from, let to = refresh.to, let window = SourceWindow(from: from, to: to),
        let minutes = refresh.minutes, minutes <= 1440, let rate = SourceEvery(minutes: minutes)
      else { return nil }
      self = .interval(rate, window, market: refresh.market)
    case .tradingDay:
      guard let market = refresh.market, let at = refresh.at.flatMap(TimeOfDay.init) else { return nil }
      self = .tradingDay(market, at: at)
    case .once:
      guard let at = refresh.at.flatMap(Timestamp.parseISO8601) else { return nil }
      self = .once(at)
    }
  }

  /// The same, as a panel file and `loci schedule` write it.
  public var refresh: PanelRefresh {
    switch self {
    case .hour: PanelRefresh(every: .hour)
    case .day(let at): PanelRefresh(every: .day, at: at.description)
    case .week(let day, let at): PanelRefresh(every: .week, at: at.description, weekday: day.rawValue)
    case .interval(let rate, let window, let market):
      PanelRefresh(every: .interval, from: window.from, to: window.to, minutes: rate.minutes, market: market)
    case .tradingDay(let market, let at): PanelRefresh(every: .tradingDay, at: at.description, market: market)
    case .once(let at): PanelRefresh(every: .once, at: at.description)
    }
  }

  /// The market whose trading days and time zone it follows.
  public var market: Market? {
    switch self {
    case .tradingDay(let market, _), .interval(_, _, let market?): market
    default: nil
    }
  }

  /// The moment it came due at, when it is due at `now` and last ran at `last`; `nil` when it is not due.
  /// Never having run, an hourly, daily or weekly one is due at once.
  public func due(last: Timestamp?, now: Timestamp, in zone: TimeZone, trading: TradingCalendar = .bundled)
    -> Timestamp?
  {
    if case .once(let at) = self { return at <= now && last.map { $0 < at } != false ? at : nil }
    if case .hour = self {
      let at = last.map { Timestamp(millisecondsSince1970: $0.millisecondsSince1970 + 3_600_000) } ?? now
      return at <= now ? at : nil
    }
    if last == nil {
      switch self {
      case .day, .week: return now
      default: break
      }
    }
    guard let mark = latest(atOrBefore: now, in: zone, trading: trading), last.map({ $0 < mark }) != false
    else { return nil }
    return mark
  }

  /// When it is due next: `now` when it is due already; `nil` for a moment that passed.
  public func next(last: Timestamp?, now: Timestamp, in zone: TimeZone, trading: TradingCalendar = .bundled)
    -> Timestamp?
  {
    if due(last: last, now: now, in: zone, trading: trading) != nil { return now }
    if case .once(let at) = self { return at > now && last.map { $0 < at } != false ? at : nil }
    if case .hour = self {
      return Timestamp(millisecondsSince1970: (last ?? now).millisecondsSince1970 + 3_600_000)
    }
    let zone = market?.timeZone ?? zone
    let today = Day(containing: now, in: zone)
    for offset in 0...21 {
      let times = times(on: today.adding(days: offset), in: zone, trading: trading)
      if let at = times.first(where: { $0 > now }) { return at }
    }
    return nil
  }

  /// The last moment up to `now` it was meant to come due at; `nil` for `hour`, which follows the last run. A
  /// trading day's or an interval's looks only at today: a day missed is not made up the next.
  public func latest(atOrBefore now: Timestamp, in zone: TimeZone, trading: TradingCalendar = .bundled)
    -> Timestamp?
  {
    let zone = market?.timeZone ?? zone
    let today = Day(containing: now, in: zone)
    switch self {
    case .interval, .tradingDay:
      return times(on: today, in: zone, trading: trading).last { $0 <= now }
    case .once(let at): return at <= now ? at : nil
    case .hour: return nil
    case .day, .week:
      for days in 0...7 {
        if let at = times(on: today.adding(days: -days), in: zone, trading: trading).last, at <= now {
          return at
        }
      }
      return nil
    }
  }

  /// The moments on `day` it comes due at.
  private func times(on day: Day, in zone: TimeZone, trading: TradingCalendar) -> [Timestamp] {
    if let market, !trading.opens(day, in: market) { return [] }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let start = day.start(in: zone).date
    let minutes: [Int] =
      switch self {
      case .hour, .once: []
      case .day(let at), .tradingDay(_, let at): [at.hour * 60 + at.minute]
      case .week(let weekday, let at):
        Weekday(of: day, in: zone) == weekday ? [at.hour * 60 + at.minute] : []
      case .interval(let rate, let window, _):
        Array(
          stride(
            from: window.from.hour * 60 + window.from.minute, to: window.to.hour * 60 + window.to.minute,
            by: rate.minutes))
      }
    return minutes.compactMap { minute in
      let at = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: start)
      return at.map(Timestamp.init)
    }
  }
}

extension Every: Codable {
  public init(from decoder: any Decoder) throws {
    let refresh = try PanelRefresh(from: decoder)
    guard let every = Every(refresh) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid schedule time, window, market or interval"))
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
