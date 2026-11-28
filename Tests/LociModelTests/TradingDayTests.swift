import Foundation
import Testing

@testable import LociModel

/// WT-S9: a trading day's schedule follows its market's days and clock; a schedule can run every few minutes
/// within hours, or once.
struct TradingDayTests {
  static let shanghai = TimeZone(identifier: "Asia/Shanghai") ?? .gmt

  static func at(_ text: String) throws -> Timestamp { try #require(Timestamp.parseISO8601(text)) }
  static func clock(_ text: String) throws -> TimeOfDay { try #require(TimeOfDay(text)) }

  @Test func anAShareScheduleRunsAtNineFifteenOnTradingDaysOnly() throws {
    let every = Every.tradingDay(.cn, at: try Self.clock("09:15"))
    let thursday = try Self.at("2026-11-26T15:00:00+08:00")
    #expect(
      every.due(last: thursday, now: try Self.at("2026-11-27T09:16:00+08:00"), in: .gmt)
        == (try Self.at("2026-11-27T09:15:00+08:00")))
    let friday = try Self.at("2026-11-27T09:15:00+08:00")
    #expect(
      every.next(last: friday, now: try Self.at("2026-11-27T10:00:00+08:00"), in: .gmt)
        == (try Self.at("2026-11-30T09:15:00+08:00")))
  }

  @Test func anAnnouncedHolidayAndTheWeekendAroundItAreSkipped() throws {
    let every = Every.tradingDay(.cn, at: try Self.clock("09:15"))
    let before = try Self.at("2026-09-30T15:00:00+08:00")
    #expect(every.due(last: before, now: try Self.at("2026-10-05T09:20:00+08:00"), in: .gmt) == nil)
    #expect(
      every.next(last: before, now: try Self.at("2026-10-01T08:00:00+08:00"), in: .gmt)
        == (try Self.at("2026-10-08T09:15:00+08:00")))
    let saturdayWorked = try #require(Day("2026-10-10"))
    #expect(!TradingCalendar.bundled.opens(saturdayWorked, in: .cn))
  }

  @Test func aYearTheCalendarDoesNotCoverGoesByWeekdaysAndSaysSo() throws {
    let every = Every.tradingDay(.cn, at: try Self.clock("09:15"))
    let newYear = try Self.at("2027-01-01T09:15:00+08:00")
    #expect(!TradingCalendar.bundled.covers(newYear, in: .cn))
    #expect(TradingCalendar.bundled.covers(try Self.at("2026-12-31T09:15:00+08:00"), in: .cn))
    #expect(every.due(last: try Self.at("2026-12-31T15:00:00+08:00"), now: newYear, in: .gmt) == newYear)
  }

  @Test func aUSScheduleKeepsNewYorkTimeAcrossDaylightSaving() throws {
    let every = Every.tradingDay(.us, at: try Self.clock("09:30"))
    let friday = try Self.at("2026-03-06T14:30:00Z")
    #expect(every.due(last: try Self.at("2026-03-05T14:30:00Z"), now: friday, in: Self.shanghai) == friday)
    #expect(
      every.next(last: friday, now: try Self.at("2026-03-06T15:00:00Z"), in: Self.shanghai)
        == (try Self.at("2026-03-09T13:30:00Z")))
    let thursday = try Self.at("2026-04-02T13:30:00Z")
    #expect(
      every.next(last: thursday, now: try Self.at("2026-04-02T15:00:00Z"), in: Self.shanghai)
        == (try Self.at("2026-04-06T13:30:00Z")))
  }

  @Test func anIntervalRunsFromTheStartOfItsHoursUpToButNotAtTheirEnd() throws {
    let morning = try #require(SourceWindow(from: try Self.clock("09:30"), to: try Self.clock("11:30")))
    let every = Every.interval(try #require(SourceEvery(minutes: 10)), morning, market: .cn)
    let last = try Self.at("2026-11-27T11:20:00+08:00")
    #expect(every.due(last: last, now: try Self.at("2026-11-27T11:30:00+08:00"), in: .gmt) == nil)
    #expect(
      every.next(last: last, now: try Self.at("2026-11-27T11:30:00+08:00"), in: .gmt)
        == (try Self.at("2026-11-30T09:30:00+08:00")))
    #expect(
      every.due(last: last, now: try Self.at("2026-11-30T09:47:00+08:00"), in: .gmt)
        == (try Self.at("2026-11-30T09:40:00+08:00")))
  }

  @Test func aMomentComesDueOnceAndOneAlreadyPastWhenSetNever() throws {
    let at = try Self.at("2026-11-27T12:24:00+08:00")
    let every = Every.once(at)
    let created = try Self.at("2026-11-27T12:00:00+08:00")
    let later = try Self.at("2026-11-27T12:40:00+08:00")
    #expect(every.next(last: created, now: created, in: .gmt) == at)
    #expect(every.due(last: created, now: later, in: .gmt) == at)
    #expect(every.due(last: at, now: later, in: .gmt) == nil)
    #expect(every.next(last: at, now: later, in: .gmt) == nil)
    #expect(Every.once(created).due(last: at, now: later, in: .gmt) == nil)
  }

  @Test func eachNewKindIsWrittenAsLociScheduleTakesIt() throws {
    for json in [
      #"{"every":"trading-day","market":"cn","at":"09:15"}"#,
      #"{"every":"interval","minutes":10,"from":"09:30","to":"15:00","market":"cn"}"#,
      #"{"every":"once","at":"2026-11-27T12:24:00+08:00"}"#,
    ] {
      let every = try JSONDecoder().decode(Every.self, from: Data(json.utf8))
      let again = try JSONDecoder().decode(Every.self, from: JSONEncoder().encode(every))
      #expect(again == every)
    }
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(Every.self, from: Data(#"{"every":"trading-day","at":"09:15"}"#.utf8))
    }
  }
}
