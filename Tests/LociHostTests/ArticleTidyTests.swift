import Foundation
import LociModel
import Testing

@testable import LociHost

/// Tidying an article on request (TD-S2 to TD-S5).
struct ArticleTidyTests {
  static let notes =
    (["# Notes on tail latency", "Paragraph 1 about **queueing**."] + (2...8).map { "Paragraph \($0) about queueing." }
    + ["![A chart](https://example.com/chart.png)", "Continue reading: Another article"])
    .joined(separator: "\n\n") + "\n"

  static func tidied(_ host: LocalHost, _ item: EntityID) async -> ItemPage? {
    await value(host.subscribe(OneItem(item: item))) {
      $0.tidying == nil && $0.translating == nil && $0.text?.contains("Continue reading") == false
    }
  }

  @Test func tidyingReplacesTheTextInPlace() async throws {
    try await withMediaHost { host, world in
      let item = try await host.run(AddTextItem(fileName: "notes.md", text: Self.notes))

      _ = try await host.run(TidyArticle(item: item.id))
      let page = await Self.tidied(host, item.id)

      let text = try #require(page?.text)
      #expect(text.contains("Paragraph 8 about queueing."))
      #expect(text.contains("![A chart](https://example.com/chart.png)"))
      #expect(world.agent.requests == ["tidy"])
    }
  }

  @Test func aTranslatedArticleIsTranslatedAgainFromTheTidiedText() async throws {
    try await withMediaHost { host, world in
      let item = try await host.run(AddTextItem(fileName: "notes.md", text: Self.notes))
      _ = try await host.run(TranslateArticle(item: item.id))
      #expect(
        await value(host.subscribe(OneItem(item: item.id))) {
          $0.translating == nil && $0.translation?.passages.count == 10
        } != nil)

      _ = try await host.run(TidyArticle(item: item.id))
      #expect(await job(host, item.id) { $0 == nil } != nil)
      let page = try await host.itemPage(item.id)

      #expect(page.text?.contains("Continue reading") == false)
      #expect(page.translation?.passages.map(\.source).last == "Paragraph 8 about queueing.")
      #expect(page.translation?.passages.count == 9)
      #expect(world.agent.requests.contains("tidy"))
    }
  }

  @Test func aTidyingThatLosesSomeOfTheArticleLeavesItAsItWas() async throws {
    try await withMediaHost { host, world in
      let item = try await host.run(AddTextItem(fileName: "notes.md", text: Self.notes))
      world.agent.answerTidying { _ in "# Notes on tail latency\n\nJust a summary." }

      _ = try await host.run(TidyArticle(item: item.id))
      let failed = await value(host.subscribe(OneItem(item: item.id))) {
        if case .failed = $0.tidying { true } else { false }
      }

      #expect(failed?.text == Self.notes)
      #expect(world.agent.requests == ["tidy", "tidy"])
    }
  }

  @Test func aModelThatFailsLeavesTheArticleAndCanBeAskedAgain() async throws {
    try await withMediaHost { host, world in
      let item = try await host.run(AddTextItem(fileName: "notes.md", text: Self.notes))
      world.agent.fail("the model ran out of time")

      _ = try await host.run(TidyArticle(item: item.id))
      let failed = await value(host.subscribe(OneItem(item: item.id))) { $0.tidying != nil && !Self.running($0) }
      #expect(failed?.tidying == .failed("the model ran out of time"))
      #expect(failed?.text == Self.notes)

      world.agent.fail(nil)
      _ = try await host.run(TidyArticle(item: item.id))
      #expect(await Self.tidied(host, item.id) != nil)
    }
  }

  @Test func keyPointsMoveToTheirTidiedPassages() async throws {
    try await withMediaHost { host, world in
      let item = try await host.run(AddTextItem(fileName: "notes.md", text: Self.notes))
      _ = try await host.run(PickKeyPoints(item: item.id, choice: .standard))
      let picked = await value(host.subscribe(ItemKeyPoints(item: item.id))) {
        $0.keyPoints != nil && $0.picking == nil
      }
      #expect(picked?.keyPoints?.points.compactMap(\.passage?.text).contains("Paragraph 1 about **queueing**.") == true)
      world.agent.answerTidying { piece in
        piece.replacing("**queueing**", with: "queueing").replacing("Continue reading: Another article", with: "")
      }

      _ = try await host.run(TidyArticle(item: item.id))
      #expect(await Self.tidied(host, item.id) != nil)

      let moved = try #require(try await host.keyPointsPage(item.id).keyPoints)
      #expect(moved.points.count == picked?.keyPoints?.points.count)
      #expect(moved.points.compactMap(\.passage?.text).contains("Paragraph 1 about queueing."))
      #expect(!moved.points.compactMap(\.passage?.text).contains("Paragraph 1 about **queueing**."))
    }
  }

  @Test func onlyAnArticleWithTextIsTidied() async throws {
    try await withMediaHost { host, world in
      let item = try await KeyPointScenarioTests.video(host, world)
      await #expect(throws: HostError.self) { try await host.run(TidyArticle(item: item.id)) }
      #expect(!world.agent.requests.contains("tidy"))
    }
  }

  private static func running(_ page: ItemPage) -> Bool {
    if case .running = page.tidying { true } else { false }
  }
}
