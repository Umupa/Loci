import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// DS-S2, WT-S3: the app fetches each source by itself, as often as it says whether the window is in front or
/// not, only within its window, beside whatever the companion is doing, and no more than
/// `SourceLine.startsPerMinute` fetches a minute in all.
@Suite(.timeLimit(.minutes(1)))
struct SourceLineTests {
  static let records: [String: SourceRecord] = ["513870": ["premium": .number(0.159)]]

  static func source(window: SourceWindow? = nil) -> DataSource {
    DataSource(
      name: "prem", title: "ETF 溢价", every: SourceEvery(minutes: 1)!, window: window, script: "function requests() {}")
  }

  /// Waits a moment for fetches the line started on its own after others ended.
  static func settled(_ runner: FakeSources, fetches: Int) async {
    for _ in 0..<100 where runner.finished < fetches { try? await Task.sleep(for: .milliseconds(10)) }
    try? await Task.sleep(for: .milliseconds(50))
  }

  /// One look of the fetching line, waited out.
  static func look(_ host: LocalHost) async -> Int {
    let started = await host.sourceLine.look()
    for fetch in started { await fetch.value }
    return started.count
  }

  @Test func aSourceIsFetchedAtItsFrequencyWhileTheWindowIsInTheBackground() async throws {
    let runner = FakeSources(records: Self.records)
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(Self.source()))
      #expect(await Self.look(host) == 0)

      world.advance(minutes: 1)
      #expect(await Self.look(host) == 1)

      world.advance(minutes: 1)
      #expect(await Self.look(host) == 1)
      #expect(runner.fetches == 3)
      #expect(try await host.run(ListDataSources()).first?.snapshot?.fetched == world.now)
    }
  }

  @Test func noMoreFetchesStartInAMinuteThanTheBudgetAndTheRestWaitForTheNext() async throws {
    let runner = FakeSources(records: Self.records)
    try await withHost(sources: runner) { host, _, world in
      let count = SourceLine.startsPerMinute + 4
      for index in 0..<count {
        let source = Self.source()
        _ = try await host.run(
          SaveDataSource(
            DataSource(name: "prem\(index)", title: source.title, every: source.every, script: source.script)))
      }
      let saved = runner.fetches
      world.advance(minutes: 1)
      for _ in 0..<count { _ = await Self.look(host) }
      await Self.settled(runner, fetches: saved + SourceLine.startsPerMinute)
      #expect(runner.fetches == saved + SourceLine.startsPerMinute)

      world.advance(minutes: 1)
      _ = await Self.look(host)
      await Self.settled(runner, fetches: saved + count)
      #expect(runner.fetches >= saved + count)
    }
  }

  @Test func nothingIsFetchedOutsideItsWindowOrOnAWeekendWhenOnlyWeekdays() async throws {
    let runner = FakeSources(records: Self.records)
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(Self.source(window: SourceWindow("09:30-15:00", weekdays: true))))

      world.set(to: "09:29")
      #expect(await Self.look(host) == 0)
      world.set(to: "09:30")
      #expect(await Self.look(host) == 1)
      world.set(to: "15:00")
      #expect(await Self.look(host) == 0)
      world.set(to: "10:00", daysLater: 5)
      #expect(await Self.look(host) == 0)
      world.set(to: "10:00", daysLater: 2)
      #expect(await Self.look(host) == 1)
    }
  }

  @Test func aSourceBeingFetchedIsNotFetchedAgainUntilItIsDone() async throws {
    let runner = FakeSources(records: Self.records)
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(Self.source()))
      runner.hold()
      world.advance(minutes: 1)
      let first = await host.sourceLine.look()

      world.advance(minutes: 1)
      let second = await host.sourceLine.look()
      runner.release()
      for fetch in first { await fetch.value }

      #expect(first.count == 1)
      #expect(second.isEmpty)
      world.advance(minutes: 1)
      #expect(await Self.look(host) == 1)
    }
  }

  @Test func noSourceWaitsBehindOthersThatAreDueAsOften() async throws {
    let runner = FakeSources(records: Self.records)
    try await withHost(sources: runner) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let names = ["a", "b", "c", "d", "e"]
      for (index, name) in names.enumerated() {
        let source = DataSource(name: name, title: name, every: SourceEvery(minutes: 1)!, script: "x")
        let session = LocalSession.conversation(index < 3 ? .main : .project(project))
        _ = await Background.call(SaveDataSource(source), from: session, on: host)
      }
      runner.hold()

      for _ in 0..<3 {
        world.advance(minutes: 1)
        let started = await host.sourceLine.look()
        #expect(started.count <= SourceLine.most)
        runner.release()
        for fetch in started { await fetch.value }
        runner.hold()
      }
      runner.release()
      for _ in 0..<200 where runner.finished < runner.fetches { try await Task.sleep(for: .milliseconds(10)) }

      let fetched = Dictionary(grouping: runner.names.dropFirst(names.count), by: \.self).mapValues(\.count)
      #expect(names.allSatisfy { (fetched[$0] ?? 0) >= 2 }, "\(fetched)")
    }
  }

  @Test func aFetchOfADefinitionSavedOverSinceNeverWritesOverTheNewOne() async throws {
    let runner = FakeSources(records: Self.records)
    let handed = HandedOn()
    let place = Place()
    defer { place.remove() }
    let world = TestWorld(sources: runner)
    let host = try await LocalHost.start(
      root: place.root, database: place.database, environment: world.environment, refreshed: handed)
    let old = Self.source()
    let new = DataSource(name: "prem", title: "ETF 溢价", every: SourceEvery(minutes: 1)!, script: "new script")
    let newer: [String: SourceRecord] = ["513870": ["premium": .number(0.2)]]
    _ = try await host.run(SaveDataSource(old))
    runner.hold(script: old.script)
    world.advance(minutes: 1)
    let stale = await host.sourceLine.look()

    runner.set(newer)
    _ = try await host.run(SaveDataSource(new))
    runner.set(["513870": ["premium": .number(0.1)]])
    runner.fail(.script(SourceProblems("parse", "old script"), sample: nil))
    runner.release()
    for fetch in stale { await fetch.value }

    let snapshot = try #require(try host.database.sourceSnapshot(SourceKey(.chat, "prem")))
    #expect(runner.finished == 3)
    #expect(snapshot.records == newer && !snapshot.isStale && snapshot.breakage == nil)
    #expect(place.store.dataSource(named: "prem", in: DataSourceFolder(.chat)) == new)
    #expect(place.store.samples(of: "prem", in: DataSourceFolder(.chat)).count == 2)
    #expect(await handed.all.count == 2)
    await host.close()
  }

  @Test func fetchingGoesOnWhileLociIsAnswering() async throws {
    let runner = FakeSources(records: Self.records)
    try await withHost(agent: FakeAgent { _ in .hang }, sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(Self.source()))
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      runner.set(["513870": ["premium": .number(0.2)]])
      world.advance(minutes: 1)

      world.tick()

      var premium: SourceValue?
      for _ in 0..<500 where premium != .number(0.2) {
        try await Task.sleep(for: .milliseconds(10))
        premium = try await host.run(ListDataSources()).first?.snapshot?.records["513870"]?["premium"]
      }
      #expect(premium == .number(0.2))
      #expect(await host.loci.isWorking)
      _ = try await host.run(StopTurn(in: .main))
    }
  }

  @Test func aFailedTryWaitsItsTurnLikeOneThatWorked() async throws {
    let runner = FakeSources(records: Self.records)
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(Self.source()))
      runner.fail(.unreachable(SourceProblems("requests[0]", "HTTP 502")))
      world.advance(minutes: 1)
      #expect(await Self.look(host) == 1)

      #expect(await Self.look(host) == 0)
      let snapshot = try #require(try await host.run(ListDataSources()).first?.snapshot)
      #expect(snapshot.isStale && !snapshot.isBroken)
      #expect(snapshot.records == Self.records)
    }
  }

  @Test func aFetchKeptFirstIsHandedOnBeforeOneKeptAfterIt() async throws {
    let runner = FakeSources(records: Self.records)
    let handed = HandedOnHeld()
    let place = Place()
    defer { place.remove() }
    let world = TestWorld(sources: runner)
    let host = try await LocalHost.start(
      root: place.root, database: place.database, environment: world.environment, refreshed: handed)
    let saving = Task { try await host.run(SaveDataSource(Self.source())) }
    for _ in 0..<500 where await handed.log.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

    runner.set(["513870": ["premium": .number(0.2)]])
    world.advance(minutes: 1)
    let later = await host.sourceLine.look()
    for _ in 0..<50 where runner.finished < 2 { try await Task.sleep(for: .milliseconds(10)) }
    try await Task.sleep(for: .milliseconds(50))
    await handed.letGo()
    _ = try await saving.value
    for fetch in later { await fetch.value }

    #expect(runner.finished == 2)
    #expect(await handed.log == ["begin 0.159", "end 0.159", "begin 0.2", "end 0.2"])
    await host.close()
  }

  @Test func eachFetchThatWorksIsHandedOnOnceItsSnapshotIsWritten() async throws {
    let runner = FakeSources(records: Self.records)
    let handed = HandedOn()
    let place = Place()
    defer { place.remove() }
    let world = TestWorld(sources: runner)
    let host = try await LocalHost.start(
      root: place.root, database: place.database, environment: world.environment, refreshed: handed)

    _ = try await host.run(SaveDataSource(Self.source()))
    runner.fail(.unreachable(SourceProblems("requests[0]", "HTTP 502")))
    world.advance(minutes: 1)
    _ = await Self.look(host)

    #expect(await handed.all == [SourceKey(.chat, "prem")])
    #expect(await handed.written)
    await host.close()
  }
}

/// Each source handed on after a fetch, and whether its snapshot was there by then.
actor HandedOn: SourceRefreshed {
  private(set) var all: [SourceKey] = []
  private(set) var written = false

  func refreshed(_ source: SourceKey, _ snapshot: SourceSnapshot) async {
    all.append(source)
    written = snapshot.records == SourceLineTests.records
  }
}

/// Each fetch handed on, as it begins and ends; the first is held until let go.
actor HandedOnHeld: SourceRefreshed {
  private(set) var log: [String] = []
  private var gate: CheckedContinuation<Void, Never>?
  private var holds = true

  func refreshed(_ source: SourceKey, _ snapshot: SourceSnapshot) async {
    let premium = if case .number(let value)? = snapshot.records["513870"]?["premium"] { "\(value)" } else { "-" }
    log.append("begin \(premium)")
    if holds {
      holds = false
      await withCheckedContinuation { gate = $0 }
    }
    log.append("end \(premium)")
  }

  func letGo() {
    gate?.resume()
    gate = nil
  }
}
