import Foundation
import Testing

@testable import LociModel

/// WK-S1, WK-S7: a schedule comes due at its time; one missed while the Mac slept comes due once.
struct EveryTests {
  static let zone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt

  /// A moment on 2025-11-17, a Monday in Shanghai, or `days` later.
  static func at(_ time: String, days: Int = 0) -> Timestamp {
    let day = (Day("2025-11-17") ?? Day(containing: Timestamp(millisecondsSince1970: 0), in: zone)).adding(days: days)
    let clock = TimeOfDay(time) ?? TimeOfDay(of: Timestamp(millisecondsSince1970: 0), in: .gmt)
    return Timestamp(
      millisecondsSince1970: day.start(in: zone).millisecondsSince1970 + Int64(clock.hour * 60 + clock.minute) * 60_000)
  }

  static func clock(_ time: String) throws -> TimeOfDay { try #require(TimeOfDay(time)) }

  @Test func aDailyScheduleIsDueAtItsTimeAndSaysWhen() throws {
    let daily = Every.day(at: try Self.clock("21:00"))
    let set = Self.at("20:00")

    #expect(daily.due(last: set, now: Self.at("20:59"), in: Self.zone) == nil)
    #expect(daily.due(last: set, now: Self.at("21:00"), in: Self.zone) == Self.at("21:00"))
    #expect(daily.next(last: set, now: Self.at("20:00"), in: Self.zone) == Self.at("21:00"))
    #expect(daily.next(last: Self.at("21:00"), now: Self.at("21:30"), in: Self.zone) == Self.at("21:00", days: 1))
  }

  @Test func aTimeMissedSeveralTimesIsDueOnceAtTheLatestMiss() throws {
    let daily = Every.day(at: try Self.clock("21:00"))
    let asleep = Self.at("21:00", days: -4)

    #expect(daily.due(last: asleep, now: Self.at("08:00"), in: Self.zone) == Self.at("21:00", days: -1))
    #expect(daily.due(last: Self.at("08:00"), now: Self.at("09:00"), in: Self.zone) == nil)
  }

  @Test func aWeeklyScheduleWaitsForItsDay() throws {
    let fridays = Every.week(.friday, at: try Self.clock("10:00"))

    #expect(fridays.due(last: Self.at("08:00"), now: Self.at("10:00", days: 3), in: Self.zone) == nil)
    #expect(
      fridays.due(last: Self.at("08:00"), now: Self.at("10:00", days: 4), in: Self.zone) == Self.at("10:00", days: 4))
    #expect(fridays.next(last: Self.at("08:00"), now: Self.at("08:00"), in: Self.zone) == Self.at("10:00", days: 4))
  }

  @Test func anHourlyScheduleIsDueAnHourAfterItsLastRun() {
    #expect(Every.hour.due(last: Self.at("08:10"), now: Self.at("09:09"), in: Self.zone) == nil)
    #expect(Every.hour.due(last: Self.at("08:10"), now: Self.at("09:10"), in: Self.zone) == Self.at("09:10"))
    #expect(Every.hour.next(last: Self.at("08:10"), now: Self.at("08:30"), in: Self.zone) == Self.at("09:10"))
  }

  @Test func aPanelsRefreshIsReadAsTheSameScheduleAndWrittenBackAlike() throws {
    let refresh = PanelRefresh(every: .week, at: "10:00", weekday: 6)
    let every = try #require(Every(refresh))

    #expect(every == .week(.friday, at: try Self.clock("10:00")))
    #expect(every.refresh == refresh)
    #expect(Every(PanelRefresh(every: .day)) == nil)
    let json = try JSONEncoder().encode(every)
    #expect(try JSONDecoder().decode(PanelRefresh.self, from: json) == refresh)
  }

  @Test func aFollowUpTimeIsReadInTheHostsTimeZone() throws {
    let now = Self.at("22:00")
    let day = try #require(Day("2025-11-21"))

    #expect(FollowUpTime.at(day, nil).moment(now: now, in: Self.zone) == Self.at("09:00", days: 4))
    #expect(FollowUpTime.next(try Self.clock("21:00")).moment(now: now, in: Self.zone) == Self.at("21:00", days: 1))
    #expect(FollowUpTime.next(try Self.clock("23:00")).moment(now: now, in: Self.zone) == Self.at("23:00"))
    #expect(FollowUpTime.after(minutes: 90).moment(now: now, in: Self.zone) == Self.at("23:30"))
  }

  @Test func aWeekdayIsReadFromItsName() {
    #expect(Weekday(name: "Fri") == .friday)
    #expect(Weekday(name: "sunday") == .sunday)
    #expect(Weekday(name: "fr") == nil)
  }
}

/// WK-S7: the inbox keeps one event for each timer that came due.
struct EventTests {
  @Test func anEventsKeyNamesItsTimerAndWhenItCameDue() {
    let due = Timestamp(millisecondsSince1970: 1_763_337_600_000)
    let later = Timestamp(millisecondsSince1970: 1_763_337_660_000)
    let schedule = Event(id: Fixture.id(1), source: .schedule(Fixture.item, project: nil), due: due)

    #expect(schedule.key == Event(id: Fixture.id(2), source: .schedule(Fixture.item, project: nil), due: due).key)
    #expect(schedule.key != Event(id: Fixture.id(3), source: .schedule(Fixture.item, project: nil), due: later).key)
    #expect(
      Event(id: Fixture.id(4), source: .panel(PanelRef("radar"), asked: true), due: due).key
        != Event(id: Fixture.id(5), source: .panel(PanelRef("radar"), asked: false), due: due).key)
    #expect(
      Event(id: Fixture.id(6), source: .followUp(Fixture.item, project: nil), due: due).key
        == Event(id: Fixture.id(7), source: .followUp(Fixture.item, project: nil), due: later).key)
  }

  @Test func anEventAndARunSurviveJSON() throws {
    let retry = Event.Retry(run: Fixture.id(9), tries: 2, notBefore: Timestamp(millisecondsSince1970: 5))
    let event = Event(
      id: Fixture.id(1), source: .panel(PanelRef("radar"), asked: true), due: .init(millisecondsSince1970: 0)
    )
    .with(.waiting(retry))
    let run = Run(
      id: Fixture.id(9),
      kind: .timers(Run.Timed(.schedule(Fixture.item, project: nil), [.followUp(Fixture.id(3), project: nil)])),
      startedAt: .init(millisecondsSince1970: 0), outcome: .finished(summary: "发了 v0.9。", sources: ["https://a"]),
      record: "runs/2025-11-17/x.md")

    #expect(try HostCodingTests.roundTrips(event))
    #expect(try HostCodingTests.roundTrips(run))
    #expect(!event.with(.dropped).state.isOpen)
  }
}
