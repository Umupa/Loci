import Foundation
import LociModel
import Testing

@testable import LociStore

/// WK-S7: the inbox keeps what is to be done across quitting, once for each timer that came due.
struct InboxTests {
  static func at(_ minutes: Int64) -> Timestamp {
    Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + minutes * 60_000)
  }

  static func event(_ seed: UInt64, _ source: Event.Source, due minutes: Int64 = 0) -> Event {
    Event(id: Fixture.id(seed), source: source, due: at(minutes))
  }

  @Test func raisingTheSameTimerAtTheSameMomentKeepsOneEvent() throws {
    let database = try StoreDatabase.inMemory()

    #expect(try database.raise(Self.event(10, .schedule(Fixture.id(1)))))
    #expect(try !database.raise(Self.event(11, .schedule(Fixture.id(1)))))
    #expect(try database.raise(Self.event(12, .schedule(Fixture.id(1)), due: 60)))
    #expect(try database.openEvents().map(\.id) == [Fixture.id(10), Fixture.id(12)])
  }

  @Test func anEventDoneOrDroppedIsNoLongerOpenButStillKeepsItsKey() throws {
    let database = try StoreDatabase.inMemory()
    let done = Self.event(10, .followUp(Fixture.id(1)))
    let dropped = Self.event(11, .panel("radar", asked: false))
    try database.raise(done)
    try database.raise(dropped)

    try database.update(done.with(.done(Fixture.id(20))))
    try database.update(dropped.with(.dropped))

    #expect(try database.openEvents().isEmpty)
    #expect(try !database.raise(Self.event(12, .followUp(Fixture.id(1)))))
    #expect(try database.event(Fixture.id(10))?.state == .done(Fixture.id(20)))
  }

  @Test func aRunCutShortByQuittingIsWaitingAgainForTheSameRunWithoutCountingATry() throws {
    let database = try StoreDatabase.inMemory()
    let event = Self.event(10, .schedule(Fixture.id(1)))
    try database.raise(event)
    try database.update(event.with(.running(Fixture.id(20), tries: 1)))

    try database.recoverRunning()

    let retry = Event.Retry(run: Fixture.id(20), tries: 1, notBefore: nil)
    #expect(try database.openEvents().map(\.state) == [.waiting(retry)])
  }
}

/// WK-S1, WK-S2, WK-S6: the schedules and follow-ups the companion set.
struct TimerTableTests {
  static func schedule(_ seed: UInt64, _ name: String, paused: Bool = false) -> Schedule {
    Schedule(
      id: Fixture.id(seed), name: name, title: "动静", follow: "看看 CubeSandbox", every: .hour,
      destination: .notes, paused: paused, createdAt: Fixture.instant)
  }

  @Test func aScheduleIsKeptAsItWasLastSaved() throws {
    let database = try StoreDatabase.inMemory()
    try database.saveSchedule(Self.schedule(1, "news"))

    try database.saveSchedule(Self.schedule(1, "news", paused: true))

    #expect(try database.schedules() == [Self.schedule(1, "news", paused: true)])
    try database.removeSchedule(Fixture.id(1))
    #expect(try database.schedules().isEmpty)
  }

  @Test func twoSchedulesCannotShareAName() throws {
    let database = try StoreDatabase.inMemory()
    try database.saveSchedule(Self.schedule(1, "news"))

    #expect(throws: (any Error).self) { try database.saveSchedule(Self.schedule(2, "news")) }
  }

  @Test func aFollowUpLeavesTheListOnceItCameDueOrWasCancelledAndIsStillFound() throws {
    let database = try StoreDatabase.inMemory()
    let soon = FollowUp(
      id: Fixture.id(1), due: InboxTests.at(10), what: "看看 #244", conversation: .main, createdAt: Fixture.instant)
    let later = FollowUp(
      id: Fixture.id(2), due: InboxTests.at(60), what: "再看", conversation: nil, createdAt: Fixture.instant)
    try database.addFollowUp(later)
    try database.addFollowUp(soon)
    #expect(try database.followUps() == [soon, later])

    #expect(try database.endFollowUp(soon.id, at: InboxTests.at(10)))
    #expect(try !database.endFollowUp(soon.id, at: InboxTests.at(11)))

    #expect(try database.followUps() == [later])
    #expect(try database.followUp(soon.id) == soon)
  }
}

/// WK-S2, WK-S3, WK-S5, WK-S6: what each run did, by schedule, and its record.
struct RunTableTests {
  static func run(_ seed: UInt64, _ sources: Run.Timed, minutes: Int64, _ outcome: Run.Outcome) -> Run {
    Run(
      id: Fixture.id(seed), kind: .timers(sources), startedAt: InboxTests.at(minutes), outcome: outcome,
      record: Store.runRecordPath(of: Fixture.id(seed), on: Day(containing: InboxTests.at(minutes), in: .gmt)))
  }

  @Test func aSchedulesRunsComeNewestFirstAlsoWhenTheyWereSharedWithAnother() throws {
    let database = try StoreDatabase.inMemory()
    let news = ScheduleRef.schedule(Fixture.id(1))
    let first = Self.run(10, Run.Timed(.schedule(Fixture.id(1))), minutes: 0, .running(tries: 0))
    let shared = Self.run(
      11, Run.Timed(.panel("radar", asked: false), [.schedule(Fixture.id(1))]), minutes: 60,
      .finished(summary: "没有新动静。", sources: []))
    try database.saveRun(first)
    try database.saveRun(shared)
    try database.saveRun(first.with(.failed("gone", tries: 3)))

    #expect(try database.runs(of: news, limit: 5) == [shared, first.with(.failed("gone", tries: 3))])
    #expect(try database.runs(of: .panel("radar"), limit: 5) == [shared])
    #expect(try database.runs(startedAfter: InboxTests.at(30)) == [shared])
  }

  @Test func aFollowUpsRunIsUntoldUntilTheMainConversationIsToldOnceItIsOver() throws {
    let database = try StoreDatabase.inMemory()
    let running = Self.run(10, Run.Timed(.followUp(Fixture.id(1))), minutes: 0, .running(tries: 1))
    let failed = Self.run(11, Run.Timed(.followUp(Fixture.id(2))), minutes: 5, .failed("unreachable", tries: 3))
    let schedule = Self.run(12, Run.Timed(.schedule(Fixture.id(3))), minutes: 6, .finished(summary: "x", sources: []))
    for run in [running, failed, schedule] { try database.saveRun(run) }

    #expect(try database.untoldFollowUpRuns() == [failed])
    try database.markTold([failed.id], at: InboxTests.at(9))
    #expect(try database.untoldFollowUpRuns().isEmpty)
  }

  @Test func aRunsRecordIsWrittenUnderTheDayItStarted() throws {
    try withStore { store in
      let path = Store.runRecordPath(of: Fixture.id(10), on: Day(containing: Fixture.instant, in: .gmt))

      try store.saveRunRecord("# run\n", at: path)

      #expect(path.hasPrefix("runs/\(Day(containing: Fixture.instant, in: .gmt))/"))
      #expect(try store.runRecord(at: path) == "# run\n")
      #expect(
        try store.runRecord(at: Store.runRecordPath(of: Fixture.id(11), on: Day(containing: Fixture.instant, in: .gmt)))
          == nil)
      #expect(throws: (any Error).self) { try store.saveRunRecord("x", at: "../MEMORY.md") }
    }
  }
}
