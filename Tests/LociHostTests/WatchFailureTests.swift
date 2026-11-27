import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WT-S3 when triage fails: a call to a model that is down is tried again a minute later for as long as it
/// takes, and at once when the model services change; only answers the app cannot read give a batch up, after
/// three; a batch waiting to be tried again holds back none after it; and the timers page shows a source that
/// keeps failing, with why.
@Suite(.timeLimit(.minutes(1)))
struct WatchFailureTests {
  static let entries = WatchScenarioTests.entries

  static func again(_ host: LocalHost, _ world: TestWorld, after minutes: Int64) async {
    world.advance(minutes: minutes)
    await host.watchTriage.look()
    await host.watchTriage.settled()
  }

  @Test func aCallThatFailsIsTriedAgainEveryMinuteForAsLongAsItTakes() async throws {
    let model = TriageModel.discarding()
    let sources = FakeSources()
    try await withWatchHost(model: model, sources: sources) { host, _, world in
      _ = try await host.run(SaveDataSource(Watching.news))
      await model.go(down: "api_error")
      sources.set(entries: Self.entries)
      await Watching.fetchNext(on: host, world)
      for _ in 0..<30 { await Self.again(host, world, after: WatchTriage.callRetryMinutes) }
      #expect(try host.database.waitingWatchBatches().first?.failures == 31)

      await model.go(down: nil)
      await Self.again(host, world, after: WatchTriage.callRetryMinutes)

      #expect(try host.database.waitingWatchBatches().isEmpty)
      #expect(await model.inputs.count == 32)
    }
  }

  @Test func aChangeOfTheModelServicesTriesWaitingBatchesAtOnce() async throws {
    let model = TriageModel.discarding()
    let sources = FakeSources()
    try await withWatchHost(model: model, sources: sources) { host, _, world in
      _ = try await host.run(SaveDataSource(Watching.news))
      await model.go(down: "api_error")
      sources.set(entries: Self.entries)
      await Watching.fetchNext(on: host, world)
      #expect(try host.database.waitingWatchBatches().count == 1)

      await model.go(down: nil)
      _ = try await configureModels(host)
      await host.watchTriage.settled()

      #expect(try host.database.waitingWatchBatches().isEmpty)
    }
  }

  @Test func anAnswerTheAppCannotReadGivesTheBatchUpAfterThree() async throws {
    let model = TriageModel { _ in "not json" }
    let sources = FakeSources()
    try await withWatchHost(model: model, sources: sources) { host, _, world in
      _ = try await host.run(SaveDataSource(Watching.news))
      sources.set(entries: Self.entries)
      await Watching.fetchNext(on: host, world)
      #expect(try host.database.waitingWatchBatches().first?.tries == 1)

      for minutes in Worker.retryMinutes { await Self.again(host, world, after: minutes) }

      #expect(await model.inputs.count == Worker.retryMinutes.count)
      #expect(try host.database.waitingWatchBatches().isEmpty)
    }
  }

  @Test func aBatchWaitingToBeTriedAgainHoldsBackNoNewerOneOfItsHome() async throws {
    let model = TriageModel { input in
      input.source == "news" ? "not json" : TriageDecision.reply(input.entries.map { .discard($0.id) })
    }
    let sources = FakeSources()
    try await withWatchHost(model: model, sources: sources) { host, _, world in
      _ = try await host.run(SaveDataSource(Watching.news))
      _ = try await host.run(
        SaveDataSource(DataSource(name: "flash", title: "快讯", every: Watching.news.every, script: Watching.news.script))
      )
      sources.set(entries: Self.entries)
      await Watching.fetchNext(on: host, world)

      let waiting = try host.database.waitingWatchBatches()
      #expect(waiting.map(\.batch.source.name) == ["news"])
      let asked = await model.inputs.map(\.source)
      #expect(asked.sorted() == ["flash", "news"])
    }
  }

  @Test func theTimersPageShowsASourceWhoseSortingKeepsFailingUntilItWorks() async throws {
    let model = TriageModel.discarding()
    let sources = FakeSources()
    try await withWatchHost(model: model, sources: sources) { host, _, world in
      _ = try await host.run(SaveDataSource(Watching.news))
      await model.go(down: "api_error: upstream unavailable")
      sources.set(entries: Self.entries)
      await Watching.fetchNext(on: host, world)
      #expect(try await host.run(ListTimers()).triage == [])

      await Self.again(host, world, after: WatchTriage.callRetryMinutes)
      let trouble = try await host.run(ListTimers()).triage?.first
      #expect(trouble?.title == Watching.news.title)
      #expect(trouble?.problem.contains("api_error: upstream unavailable") == true)
      #expect(trouble?.failed == 2)

      await model.go(down: nil)
      await Self.again(host, world, after: WatchTriage.callRetryMinutes)
      #expect(try await host.run(ListTimers()).triage == [])
    }
  }
}
