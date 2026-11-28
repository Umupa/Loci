import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WT-S4, WT-S5: the replay of 11-27's lunch break, with a tool model and a companion that do as they should,
/// gives one card for the State Council's market support, up by 12:30 with the afternoon's open as its deadline,
/// and none for the noise; the same news again from another outlet wakes no one. Also checks the replay's own
/// judging, which `script/eval` uses on the real Codex.
@Suite(.timeLimit(.minutes(1)))
struct WatchEvalSelfTests {
  static let key = "2026-11-27 国常会 国家队稳市"

  /// Escalates the State Council's news under one key, the second report by finding it among `recent`.
  static let model = TriageModel { input in
    TriageDecision.reply(
      input.entries.map { entry in
        guard entry.title.contains("国常会") else { return .discard(entry.id) }
        let key = input.recent.first { $0.summary.contains("国常会") }?.key ?? key
        return .escalate(entry.id, key: key, summary: "国常会：加力发挥国家队稳市作用", deadline: "2026-11-27T13:00:00+08:00")
      })
  }

  static func replay(
    _ companion: WatchCompanion, _ body: (WatchReplay.Outcome, TestWorld) async throws -> Void
  ) async throws {
    let sources = FakeSources()
    try await withWatchHost(model: model, sources: sources, companion: companion) { host, place, world in
      let project = try await ProjectScenarioTests.start(host, named: "理财")
      try place.edit(place.root.appending(path: "agent/projects/\(project)/WATCH.md")) { _ in WatchSample.watch }
      _ = await Background.call(SaveDataSource(Watching.news), from: .conversation(.project(project)), on: host)
      let replay = WatchReplay(
        host: host, world: world, sources: sources, sample: .middayOf1127, home: .project(project),
        patience: .seconds(30))
      try await body(try await replay.run(), world)
    }
  }

  @Test func theStateCouncilsNewsIsOneCardByHalfPastTwelveAndTheNoiseNone() async throws {
    let companion = WatchCompanion.carding { prompt in
      prompt.contains("2546318") ? "12:24 财联社：国常会加力发挥国家队稳市作用，13:00 开盘前可调整" : "看不到出处"
    }
    try await Self.replay(companion) { outcome, world in
      #expect(WatchReplay.problems(outcome, against: .middayOf1127).isEmpty)
      #expect(outcome.runs == 1)
      #expect(outcome.findings.map(\.key) == [Self.key])
      let prompt = try #require(Background.prompts(world, starting: WatchCompanion.prefix).first)
      #expect(prompt.contains("2026-11-27T13:00:00+08:00"))
      #expect(prompt.contains("T+1"))
    }
  }

  @Test func theReplayFindsACardThatCameLateOrSaidNoSourceOrWasNoise() {
    let sample = WatchSample.middayOf1127
    func card(_ what: String, at time: String, deadline: Timestamp? = sample.deadline) -> NextUp {
      NextUp(
        id: TestWorld().nextID(), home: .chat, key: what, kind: .ask(question: "要调整吗？"), what: what,
        shownAt: WatchSample.at(time), deadline: deadline)
    }
    let late = WatchReplay.Outcome(cards: [card("12:24 财联社 国常会", at: "12:40:00")], findings: [], runs: 1)
    let bare = WatchReplay.Outcome(cards: [card("国常会", at: "12:26:00", deadline: nil)], findings: [], runs: 1)
    let noisy = WatchReplay.Outcome(
      cards: [card("12:24 财联社 国常会", at: "12:26:00"), card("龙虎榜：游资", at: "12:45:00")], findings: [], runs: 2)

    #expect(WatchReplay.problems(late, against: sample).count == 1)
    #expect(WatchReplay.problems(bare, against: sample).count == 3)
    #expect(WatchReplay.problems(noisy, against: sample).count == 2)
    #expect(WatchReplay.problems(.init(cards: [], findings: [], runs: 0), against: sample).count == 1)
    #expect(sample.items.filter { !$0.madeUp }.map(\.entry.url) == [WatchSample.policyLink])
  }
}
