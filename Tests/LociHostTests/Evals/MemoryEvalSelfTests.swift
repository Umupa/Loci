import Foundation
import LociModel
import Testing

@testable import LociHost

/// The memory eval itself, against companions that behave as scripted: one that remembers and was corrected
/// passes, one that kept the old belief fails on exactly that question, and the cost counts what was kept.
@Suite(.timeLimit(.minutes(2)))
struct MemoryEvalSelfTests {
  static let index = "# Memory\n- 2025-11-17 阿哲，写 Go [阿哲](memory/azhe.md)\n- 2025-11-18 先给结论再给论证\n"
  static let page = "# 阿哲\n- 2025-11-19 \"上个月搬到杭州了\"\n- 2025-11-20 读完了 etcd 的选主\n"

  /// Answers questions from `answers`, keeps the wiki in its reviews, and reports how full its context is.
  static func companion(_ answers: [String: String]) -> FakeAgent {
    FakeAgent(provider: .codex) { prompt in
      if prompt.hasPrefix(MemoryScenarioTests.review) {
        return .write(["MEMORY.md": index, "memory/azhe.md": page], reply: "Done.")
      }
      let asked = answers.first { prompt.hasSuffix($0.key) }
      return .report(ContextUsage(used: 30_000, window: 400_000), reply: asked?.value ?? "嗯。")
    }
  }

  static let right = [
    "我现在住在哪个城市？": "杭州，上个月刚搬过去。", "etcd 的选主我读完了吗？原来打算什么时候读完？": "读完了，原来说下周一前。",
    "给我讲东西的时候你应该怎么讲？": "先给结论，再给论证。", "我平时主要写什么语言？": "Go。",
  ]

  static func run(_ companion: FakeAgent, judge: (any MemoryJudge)? = nil) async throws -> MemoryOutcome {
    var outcome: MemoryOutcome?
    try await withHost(agent: companion) { host, place, world in
      outcome = try await MemoryEvalRunner(
        host: host, place: place, world: world, scenario: .standard, judge: judge, patience: .seconds(20)
      ).run()
    }
    return try #require(outcome)
  }

  @Test func aCompanionThatRemembersAndWasCorrectedPassesEveryQuestion() async throws {
    let outcome = try await Self.run(Self.companion(Self.right))

    #expect(outcome.answers.count == MemoryScenario.standard.questions.count)
    let failed = outcome.answers.filter { !$0.passed }.map(\.question)
    #expect(failed.isEmpty, "\(failed)")
    #expect(outcome.problems.isEmpty, "\(outcome.problems)")
  }

  @Test func aCompanionThatKeptTheCorrectedBeliefFailsThatQuestion() async throws {
    var wrong = Self.right
    wrong["我现在住在哪个城市？"] = "你在深圳呀。"

    let outcome = try await Self.run(Self.companion(wrong))

    #expect(outcome.answers.map(\.passed) == [false, true, true, true])
    #expect(outcome.answers[0].reasons == ["答成了已经纠正过的「深圳」"])
  }

  @Test func theJudgeCanFailAnAnswerTheWordsWouldPass() async throws {
    struct Doubting: MemoryJudge {
      func grade(_ question: MemoryScenario.Question, answer: String) async -> Bool? { question.id != "style" }
    }

    let outcome = try await Self.run(Self.companion(Self.right), judge: Doubting())

    #expect(outcome.answers.map(\.passed) == [true, true, false, true])
  }

  @Test func theCostCountsTheIndexTheWikiAndTheTokensOfEveryTurnAndReview() async throws {
    let outcome = try await Self.run(Self.companion(Self.right))

    #expect(outcome.cost.indexLines == 3 && outcome.cost.wikiPages == 1)
    #expect(outcome.cost.wikiCharacters == Self.page.count)
    #expect(outcome.cost.turnTokens.count == 7 + 4 && outcome.cost.turnTokens.allSatisfy { $0 == 30_000 })
    #expect(outcome.cost.agentsCharacters > 0 && outcome.cost.checks.values.allSatisfy { $0 })
    #expect(MemoryReport.markdown(outcome, runtime: "fake").contains("wiki：1 页"))
  }
}
