import Foundation
import Testing

@testable import LociModel

struct DayTests {
  @Test func aDayAndATimeSurviveTheirTextForm() throws {
    let day = try #require(Day("2026-02-28"))

    #expect(day.description == "2026-02-28")
    #expect(Day(day.description) == day)
    #expect(try #require(TimeOfDay("7:05")).description == "07:05")
  }

  @Test func daysAndTimesTheCalendarDoesNotHaveAreRejected() {
    #expect(Day("2026-02-30") == nil)
    #expect(Day("2026-13-01") == nil)
    #expect(Day("26-01-01") == nil)
    #expect(TimeOfDay("24:00") == nil)
    #expect(TimeOfDay("12:60") == nil)
  }

  @Test func aMomentFallsOnTheDayOfItsTimeZone() throws {
    let moment = try #require(Timestamp("2026-11-17T17:30:00.000Z"))
    let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))

    #expect(Day(containing: moment, in: shanghai) == Day("2026-11-18"))
    #expect(Day(containing: moment, in: .gmt) == Day("2026-11-17"))
    #expect(TimeOfDay(of: moment, in: shanghai) == TimeOfDay("01:30"))
    #expect(try #require(Day("2026-11-18")).start(in: shanghai) == Timestamp("2026-11-17T16:00:00.000Z"))
  }

  @Test func daysCountAcrossMonthsAndYears() throws {
    let day = try #require(Day("2026-12-31"))

    #expect(day.adding(days: 1) == Day("2027-01-01"))
    #expect(day.adding(days: -365) == Day("2025-12-31"))
    #expect(try #require(Day("2026-11-01")).days(until: try #require(Day("2026-11-18"))) == 17)
  }
}
