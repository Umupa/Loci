import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WT-S9: a schedule on a market's trading days comes due straight into the inbox, with its deadline, and never
/// through triage; on a day the market is shut it does not; past the calendar's years the timers page says so.
@Suite(.timeLimit(.minutes(1)))
struct WatchScheduleTests {
  static let openSoon = ScheduleDraft(
    title: "隔夜美股", follow: "开盘前看看隔夜美股", every: .tradingDay(.cn, at: TimeOfDay(hour: 9, minute: 15)!),
    destination: .notes, deadlineMinutes: 15)

  static func at(_ text: String) -> Timestamp {
    Timestamp.parseISO8601(text) ?? Timestamp(millisecondsSince1970: 0)
  }

  static func schedules(_ host: LocalHost) throws -> [Event] {
    try host.database.openEvents().filter { if case .schedule = $0.source { true } else { false } }
  }

  @Test func aTradingDayScheduleComesDueAtItsTimeStraightIntoTheInboxWithItsDeadline() async throws {
    let model = TriageModel.discarding()
    try await withHost(agent: Background.agent { _ in .hang }, models: model) { host, _, world in
      _ = try await configureModels(host)
      world.set(to: Self.at("2026-11-27T08:00:00+08:00"))
      _ = try await Background.add("open", Self.openSoon, on: host)
      world.set(to: Self.at("2026-11-27T09:15:00+08:00"))
      await host.scheduler.look()

      let raised = try Self.schedules(host)
      #expect(raised.map(\.due) == [Self.at("2026-11-27T09:15:00+08:00")])
      #expect(raised.first?.deadline == Self.at("2026-11-27T09:30:00+08:00"))
      #expect(await model.inputs.isEmpty)
      #expect(try host.database.waitingWatchBatches().isEmpty)
    }
  }

  @Test func onADayTheMarketIsShutItDoesNotComeDue() async throws {
    try await withHost(agent: Background.agent { _ in .hang }) { host, _, world in
      world.set(to: Self.at("2026-09-30T16:00:00+08:00"))
      _ = try await Background.add("open", Self.openSoon, on: host)
      world.set(to: Self.at("2026-10-05T09:16:00+08:00"))
      await host.scheduler.look()

      #expect(try Self.schedules(host).isEmpty)
      let entry = try await host.run(ListTimers()).schedules.first
      #expect(entry?.next == Self.at("2026-10-08T09:15:00+08:00"))
      #expect(entry?.calendarUncovered == false)
    }
  }

  @Test func pastTheCalendarsYearsItGoesByWeekdaysAndTheTimersPageSaysSo() async throws {
    try await withHost(agent: Background.agent { _ in .hang }) { host, _, world in
      world.set(to: Self.at("2026-12-31T16:00:00+08:00"))
      _ = try await Background.add("open", Self.openSoon, on: host)

      let entry = try await host.run(ListTimers()).schedules.first
      #expect(entry?.next == Self.at("2027-01-01T09:15:00+08:00"))
      #expect(entry?.calendarUncovered == true)
    }
  }

  @Test func aMomentComesDueOnceAndNotAgainOnceItRan() async throws {
    try await withHost(agent: Background.agent { _ in .reply("看过了。") }) { host, _, world in
      let at = Watching.minutes(1, after: world.now)
      _ = try await Background.add(
        "once", ScheduleDraft(title: "一次", follow: "看一眼", every: .once(at), destination: .notes), on: host)
      world.advance(minutes: 1)
      world.tick()
      #expect(try await Background.ran(1, starting: Background.lookInto, on: host, world))

      world.advance(minutes: 5)
      await host.scheduler.look()
      #expect(try Self.schedules(host).isEmpty)
      #expect(try await host.run(ListTimers()).schedules.first?.next == nil)
    }
  }
}
