import Foundation

/// A stock market a schedule can follow: `cn` is Shanghai and Shenzhen, `us` the New York exchanges.
public enum Market: String, Hashable, Codable, Sendable {
  case cn, us

  public var timeZone: TimeZone {
    TimeZone(identifier: self == .cn ? "Asia/Shanghai" : "America/New_York") ?? .gmt
  }
}

/// The days each market trades on: weekdays, less the holidays its exchange announced, for the years it
/// announced. A day of a year the calendar does not cover is taken to trade when it is a weekday.
public struct TradingCalendar: Sendable {
  private let closures: [Market: Set<Day>]
  private let years: [Market: Set<Int>]

  public init(closures: [Market: Set<Day>] = [:], years: [Market: Set<Int>] = [:]) {
    self.closures = closures
    self.years = years
  }

  /// Whether the market's announced holidays reach the day of `time`, in the market's time zone.
  public func covers(_ time: Timestamp, in market: Market) -> Bool {
    years[market]?.contains(Day(containing: time, in: market.timeZone).year) == true
  }

  public func opens(_ day: Day, in market: Market) -> Bool {
    let weekday = Weekday(of: day, in: market.timeZone)
    return weekday != .saturday && weekday != .sunday && closures[market]?.contains(day) != true
  }

  /// What the exchanges have announced: SSE and SZSE for 2026, NYSE for 2026 to 2028.
  public static let bundled = TradingCalendar(
    closures: [
      .cn: Set(
        """
        2026-01-01 2026-01-02 2026-02-16 2026-02-17 2026-02-18 2026-02-19 2026-02-20 2026-02-23
        2026-04-06 2026-05-01 2026-05-04 2026-05-05 2026-06-19 2026-09-25
        2026-10-01 2026-10-02 2026-10-05 2026-10-06 2026-10-07
        """.split(whereSeparator: \.isWhitespace).compactMap { Day(String($0)) }),
      .us: Set(
        """
        2026-01-01 2026-01-19 2026-02-16 2026-04-03 2026-05-25 2026-06-19 2026-07-03 2026-09-07 2026-11-26 2026-12-25
        2027-01-01 2027-01-18 2027-02-15 2027-03-26 2027-05-31 2027-06-18 2027-07-05 2027-09-06 2027-11-25 2027-12-24
        2028-01-17 2028-02-21 2028-04-14 2028-05-29 2028-06-19 2028-07-04 2028-09-04 2028-11-23 2028-12-25
        """.split(whereSeparator: \.isWhitespace).compactMap { Day(String($0)) }),
    ], years: [.cn: [2026], .us: [2026, 2027, 2028]])
}
