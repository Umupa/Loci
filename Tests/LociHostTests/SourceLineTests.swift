import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// DS-S2: the app fetches each source by itself, as often as it says while the window is in front and at most
/// hourly while it is behind, only within its window, beside whatever the companion is doing.
@Suite(.timeLimit(.minutes(1)))
struct SourceLineTests {
  static let records: [String: SourceRecord] = ["513870": ["premium": .number(0.159)]]

  static func source(window: SourceWindow? = nil) -> DataSource {
    DataSource(
      name: "prem", title: "ETF 溢价", every: SourceEvery(minutes: 1)!, window: window, script: "function requests() {}")
  }

  /// One look of the fetching line, waited out.
  static func look(_ host: LocalHost) async -> Int {
    let started = await host.sourceLine.look()
    for fetch in started { await fetch.value }
    return started.count
  }

  @Test func aSourceIsFetchedEveryItsMinutesInFrontAndAtMostHourlyBehind() async throws {
    let runner = FakeSources(records: Self.records)
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(Self.source()))
      #expect(await Self.look(host) == 0)

      world.advance(minutes: 1)
      #expect(await Self.look(host) == 1)

      world.inFront = false
      world.advance(minutes: 1)
      #expect(await Self.look(host) == 0)
      world.advance(minutes: 58)
      #expect(await Self.look(host) == 0)
      world.advance(minutes: 1)
      #expect(await Self.look(host) == 1)
      #expect(runner.fetches == 3)
      #expect(try await host.run(ListDataSources()).first?.snapshot?.fetched == world.now)
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
