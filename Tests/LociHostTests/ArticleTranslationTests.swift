import Foundation
import LociHost
import LociModel
import Testing

/// Translating an article on request (T-S2, T-S5).
struct ArticleTranslationTests {
  static let notes =
    (["# Notes on tail latency"] + (1...25).map { "Paragraph \($0) about queueing." })
    .joined(separator: "\n\n") + "\n\n```\nlet x = 1\n```\n"

  @Test func aForeignArticleIsTranslatedABatchAtATimeAndSavedAsItGoes() async throws {
    try await withMediaHost { host, world in
      let item = try await host.run(AddTextItem(fileName: "notes.md", text: Self.notes))
      #expect(try await host.itemPage(item.id).translatable)

      _ = try await host.run(TranslateArticle(item: item.id))
      let page = await value(host.subscribe(OneItem(item: item.id))) {
        $0.translating == nil && $0.translation?.passages.count == 26
      }

      let translation = try #require(page?.translation)
      #expect(translation.language == "zh-Hans")
      #expect(translation.bySource["# Notes on tail latency"] == "[zh-Hans] # Notes on tail latency")
      #expect(translation.bySource["Paragraph 25 about queueing."] == "[zh-Hans] Paragraph 25 about queueing.")
      #expect(!translation.passages.contains { $0.source.contains("let x") })
      #expect(world.agent.requests == ["passages zh-Hans 20", "passages zh-Hans 6"])
    }
  }

  @Test func askingAgainSendsOnlyWhatIsNotTranslatedYet() async throws {
    try await withMediaHost { host, world in
      let item = try await host.run(AddTextItem(fileName: "notes.md", text: Self.notes))
      world.agent.fail("the agent ran out of time")

      _ = try await host.run(TranslateArticle(item: item.id))
      let failed = await value(host.subscribe(OneItem(item: item.id))) {
        if case .failed = $0.translating { true } else { false }
      }
      #expect(failed?.translation == nil)

      world.agent.fail(nil)
      _ = try await host.run(TranslateArticle(item: item.id))
      #expect(
        await value(host.subscribe(OneItem(item: item.id))) {
          $0.translating == nil && $0.translation?.passages.count == 26
        } != nil)

      _ = try await host.run(TranslateArticle(item: item.id))
      #expect(
        await value(host.subscribe(OneItem(item: item.id))) {
          $0.translating == nil && $0.translation?.passages.count == 26
        } != nil)
      #expect(world.agent.requests.filter { $0.hasPrefix("passages") }.count == 3)
    }
  }

  @Test func anArticleInTheReadersLanguageIsNotTranslated() async throws {
    try await withMediaHost(readerLanguage: "en-US") { host, world in
      let item = try await host.run(AddLink(url: Links.url(Links.article)))
      let page = await value(host.subscribe(OneItem(item: item.id))) { $0.text != nil && $0.item.language != nil }

      #expect(page?.translatable == false)
      await #expect(throws: HostError.self) { try await host.run(TranslateArticle(item: item.id)) }
      #expect(world.agent.requests.isEmpty)
    }
  }
}
