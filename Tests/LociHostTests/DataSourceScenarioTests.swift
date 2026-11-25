import Foundation
import LociMedia
import LociModel
import LociStore
import Synchronization
import Testing

@testable import LociHost

/// DS-S1, DS-S3, DS-S14: a source saved with `loci source save` fills the panel rows that point at it, the
/// same for any Mac that watches the column.
@Suite(.timeLimit(.minutes(1)))
struct DataSourceScenarioTests {
  static let source = DataSource(
    name: "prem", title: "ETF 溢价", every: SourceEvery(minutes: 1)!, script: "function requests() {}")
  static let panel = Panel(
    name: "money", title: "ETF 溢价", follow: "x",
    body: .rows([
      .zones(
        PanelZones(
          stops: [0, 0.03, 0.1, 0.2],
          rows: [PanelZoneRow(name: "513870", value: .field(SourceField("prem.513870.premium")!))]))
    ]))

  @Test func aSavedSourceFillsThePanelRowsThatPointAtIt() async throws {
    let runner = FakeSources(records: ["513870": ["premium": .number(0.159)]])
    try await withHost(sources: runner) { host, place, world in
      _ = try await host.run(SavePanel(Self.panel))

      let outcome = try await host.run(SaveDataSource(Self.source))

      #expect(outcome == .records(["513870": ["premium": .number(0.159)]]))
      let column = try await host.panelColumn(of: .chat)
      #expect(column.readings.number(.field(SourceField("prem.513870.premium")!), of: .chat) == 0.159)
      #expect(column.readings.time(of: Self.panel, in: .chat) == PanelDataTime(fetched: world.now, stale: false))
      #expect(
        FileManager.default.fileExists(atPath: place.root.appending(path: "agent/sources/prem/source.json").path()))
      #expect(try await host.run(ListDataSources()).map(\.samples) == [1])
    }
  }

  @Test func aSourceThatFailsIsNotSavedAndSaysWhy() async throws {
    let runner = FakeSources(failure: SourceProblems("requests[0]", "HTTP 404"))
    try await withHost(sources: runner) { host, place, _ in
      let outcome = try await host.run(SaveDataSource(Self.source))

      #expect(outcome == .failed(SourceProblems("requests[0]", "HTTP 404")))
      #expect(try await host.run(ListDataSources()).isEmpty)
    }
  }

  @Test func aSourceThatCannotBeTriedIsRefusedBeforeItRuns() async throws {
    let runner = FakeSources(records: [:])
    try await withHost(sources: runner) { host, _, _ in
      let outcome = try await host.run(
        SaveDataSource(DataSource(name: "Prem", title: "x", every: SourceEvery(minutes: 1)!, script: "")))

      guard case .failed(let problems) = outcome else {
        Issue.record("saved: \(outcome)")
        return
      }
      #expect(problems.all.map(\.path) == ["name", "script"])
      #expect(runner.fetches == 0)
    }
  }

  @Test func testingReplaysTheSamplesWithANewScriptAndWritesNothing() async throws {
    let runner = FakeSources(records: ["513870": ["premium": .number(0.159)]])
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(Self.source))
      world.advance(minutes: 5)

      let replays = try await host.run(TestDataSource("prem", script: "new script"))

      #expect(replays.map(\.outcome) == [.records(["513870": ["premium": .number(0.159)]])])
      #expect(runner.replayed == ["new script"])
      #expect(try await host.run(ListDataSources()).first?.snapshot?.fetched == TestWorld.instant)
    }
  }

  @Test func aLineCutsTheHistoryOfANumberToItsSpan() async throws {
    let runner = FakeSources(records: ["513870": ["premium": .number(0.15)]])
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(Self.source))
      world.advance(minutes: 1)
      runner.set(["513870": ["premium": .number(0.16)]])
      _ = try await host.run(SaveDataSource(Self.source))

      let history = await value(
        host.subscribe(
          WatchSourceHistory(SourceKey(.chat, "prem"), field: SourceField("prem.513870.premium")!, range: .day))
      ) { _ in true }

      #expect(
        history == .points([SourcePoint(at: TestWorld.instant, value: 0.15), SourcePoint(at: world.now, value: 0.16)]))
    }
  }
}
