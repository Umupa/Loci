import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WT-S6: each fetch's numbers go to triage as fetched, beside the fetch before, so a crossing of the person's
/// line raises one finding, and staying past it raises none.
@Suite(.timeLimit(.minutes(1)))
struct WatchNumberTests {
  static let premium = DataSource(
    name: "prem", title: "QDII 溢价", every: SourceEvery(minutes: 1)!, script: "function requests() {}")

  static func premium(_ input: [String: SourceRecord]?) -> Double? {
    input?["513870"]?["premium"]?.number
  }

  /// Reads `WATCH.md`'s line as the model would: the premium falling below 3% from above it is news.
  static let model = TriageModel { input in
    guard let now = premium(input.records), let before = premium(input.previousRecords), before >= 0.03, now < 0.03
    else { return TriageDecision.reply([]) }
    return TriageDecision.reply([
      .escalate(
        nil, key: "513870 跌破 3% @\(input.recent.count)", summary: "513870 溢价 \(now)",
        deadline: "2030-01-01T15:00:00+08:00")
    ])
  }

  @Test func onlyTheFetchesThatCrossTheLineRaiseAFinding() async throws {
    let sources = FakeSources()
    try await withWatchHost(model: Self.model, sources: sources) { host, place, world in
      try place.edit(place.root.appending(path: "agent/WATCH.md")) { _ in "513870 溢价跌破 3% 告诉我。\n" }
      sources.set(["513870": ["premium": .number(0.034)]])
      _ = try await host.run(SaveDataSource(Self.premium))
      for value in [0.028, 0.027, 0.034, 0.028] {
        sources.set(["513870": ["premium": .number(value)]])
        await Watching.fetchNext(on: host, world, minutes: 1)
        await host.worker.quiet(.chat)
      }

      let inputs = await Self.model.inputs
      #expect(inputs.map { Self.premium($0.records) } == [0.028, 0.027, 0.034, 0.028])
      #expect(inputs.map { Self.premium($0.previousRecords) } == [0.034, 0.028, 0.027, 0.034])
      #expect(try Watching.raised(host).map(\.summary) == ["513870 溢价 0.028", "513870 溢价 0.028"])
      #expect(inputs.allSatisfy { $0.watch == "513870 溢价跌破 3% 告诉我。\n" })
    }
  }

  @Test func aFetchWhoseNumbersDidNotChangeIsNotSortedAgain() async throws {
    let sources = FakeSources(records: ["513870": ["premium": .number(0.034)]])
    let model = TriageModel.discarding()
    try await withWatchHost(model: model, sources: sources) { host, _, world in
      _ = try await host.run(SaveDataSource(Self.premium))
      await Watching.fetchNext(on: host, world, minutes: 1)
      sources.set(["513870": ["premium": .number(0.031)]])
      await Watching.fetchNext(on: host, world, minutes: 1)

      #expect(await model.inputs.map { Self.premium($0.records) } == [0.031])
    }
  }
}
