import Foundation
import LociMedia
import LociModel
import LociStore
import Testing

@testable import LociHost

/// M-S4, M-S12: translation, chapters and key points go only to the model services.
struct ModelTranslationTests {
  @Test func anArticleFinishesItsTranslationStageWithConcurrentBatchesInOriginalOrder() async throws {
    try await withModelHost { host, world, network, _ in
      _ = try await configureModels(host)
      let paragraphs = (1...81).map { "This is distinct paragraph \($0)." }
      let text = (["# Article"] + paragraphs).joined(separator: "\n\n")
      let choice = ImportChoice(
        keeping: .online, quality: .audio, siteSubtitles: false, recognition: nil,
        translation: .init(language: "fr", model: nil))

      await network.batches.close()
      let item = try await host.run(AddLink(url: Links.url(Links.article), articleHTML: text, choice: choice))
      let translating = await job(host, item.id, where: isRunning(.translate))
      await network.batches.open()
      #expect(translating??.stages == [.fetchPage, .extract, .findCover, .translate])
      _ = try #require(await job(host, item.id, where: isDone))
      let translation = try #require(try await host.itemPage(item.id).translation)
      #expect(translation.passages.map(\.source) == ["# Article"] + paragraphs)
      #expect(translation.passages.map(\.text) == translation.passages.map { "translated " + $0.source })
      #expect(await network.peak == 2)
      #expect(await network.translationInputs.map(\.count).sorted() == [2, 20, 20, 20, 20])
    }
  }

  @Test func withoutAConfiguredModelTranslationWaitsAndGoesOnOnceOneIsConfigured() async throws {
    try await withModelHost { host, world, _, _ in
      var settings = try await configureModels(host)
      settings.providers[0].enabled = false
      _ = try await host.saveModelSettings(settings)
      let item = try await host.run(AddTextItem(fileName: "article.md", text: "# Article\n\nOnly a model translates."))
      _ = try await host.run(TranslateArticle(item: item.id))
      _ = try #require(await job(host, item.id, where: state(.waiting(.modelService))))
      let page = try await host.itemPage(item.id)
      #expect(page.translating == .failed("No model service is configured to translate."))

      settings.providers[0].enabled = true
      _ = try await host.saveModelSettings(settings)
      _ = try #require(await job(host, item.id, where: isDone))
      #expect(try await host.itemPage(item.id).translation?.passages.count == 2)
      #expect(world.agent.requests.isEmpty)
    }
  }

  @Test func overlappingArticlesShareTranslationsAndCacheSizeAndClearAreVisible() async throws {
    try await withModelHost { host, _, network, _ in
      _ = try await configureModels(host)
      let common = "This is in both articles."
      async let one = article(host, title: "One", paragraphs: [common, "First only."])
      async let two = article(host, title: "Two", paragraphs: [common, "Second only."])
      let (first, second) = try await (one, two)
      #expect(first.bySource[common] == second.bySource[common])
      #expect(await network.translationInputs.flatMap { $0 }.count { $0 == common } == 1)
      #expect(try await host.readModelSettings().cacheBytes > 0)

      try await host.clearTranslationCache()
      #expect(try await host.readModelSettings().cacheBytes == 0)
      let saved = try await host.itemPage(first.item).translation
      #expect(saved?.bySource[common] == first.bySource[common])
      _ = try await article(host, title: "Three", paragraphs: [common])
      #expect(await network.translationInputs.flatMap { $0 }.count { $0 == common } == 2)
    }
  }

  @Test func languageModelPromptAndFullContextAllAffectReuse() async throws {
    try await withModelHost { host, _, network, _ in
      let paragraph = "The meaning depends on the source."
      var settings = try await configureModels(host)
      _ = try await article(host, paragraphs: [paragraph])

      settings.translation.language = "ja"
      _ = try await host.saveModelSettings(settings)
      #expect(try await article(host, paragraphs: [paragraph]).language == "ja")

      settings.providers[0].models.append(ProviderModel(id: "different-model", checked: true))
      settings.translation.model = ModelChoice(provider: settings.providers[0].id, model: "different-model")
      _ = try await host.saveModelSettings(settings)
      _ = try await article(host, paragraphs: [paragraph])

      settings.translation.articlePrompt = "Write naturally in {{language}}."
      _ = try await host.saveModelSettings(settings)
      _ = try await article(host, paragraphs: [paragraph])

      settings.translation.smart = true
      _ = try await host.saveModelSettings(settings)
      _ = try await article(host, title: "Meaning one", paragraphs: [paragraph, "Context for the first meaning."])
      _ = try await article(host, title: "Meaning two", paragraphs: [paragraph, "Context for the second meaning."])
      let prompts = await network.prompts
      #expect(prompts.count == 6)
      #expect(prompts.suffix(3).allSatisfy { $0.contains("Write naturally in ja.") && $0.contains(#"{"lines":"#) })
      #expect(prompts[4].contains("Context for the first meaning."))
      #expect(prompts[4].contains("BCP 47 tag `ja`"))
      #expect(prompts[5].contains("Context for the second meaning."))
    }
  }

  @Test func aTranscriptGetsConcurrentTranslationsChaptersAndKeyPointsWithoutAnAgent() async throws {
    try await withModelHost { host, world, network, _ in
      try world.place.store.saveAgentText("I learn this to build a video course for my team.", as: .profile)
      _ = try await configureModels(
        host,
        translation: TranslationSettings(
          language: "fr", smart: true, transcriptPrompt: "Translate speech into {{language}}.",
          articlePrompt: "Only for articles."))
      let lines = (0..<122).map { "Sentence \($0)." }
      let cues = lines.enumerated().map { index, line in
        "\(Self.vtt(index * 2)) --> \(Self.vtt(index * 2 + 1))\n\(line)\n\n"
      }.joined()
      world.programs.site(Links.youtube, FakeSite(title: "A video", subtitles: "WEBVTT\n\n" + cues))
      let item = try await host.run(
        AddLink(url: Links.url(Links.youtube), why: "To see how the first upload was framed."))
      _ = try #require(await job(host, item.id, where: isDone))
      let media = try await host.run(ReadMediaPage(item: item.id))
      #expect(media.translations.first?.lines == lines.map { "translated " + $0 })
      #expect(media.outline?.chapters.map(\.title) == ["Model chapter"])
      #expect(await network.peak == 2)

      _ = try await host.run(PickKeyPoints(item: item.id, choice: KeyPointChoice(count: .few)))
      let points = await KeyPointScenarioTests.picked(host, item.id)
      #expect(points?.keyPoints?.points.map(\.title) == ["First", "Second", "Third"])
      #expect(world.agent.requests.isEmpty)
      let prompts = await network.prompts
      #expect(prompts.count { $0.contains("Translate speech into fr.") && $0.contains("Sentence 121.") } == 3)
      #expect(prompts.allSatisfy { !$0.contains("Only for articles.") })
      let picking = try #require(prompts.last)
      #expect(picking.contains("I learn this to build a video course for my team."))
      #expect(picking.contains("To see how the first upload was framed."))
    }
  }

  private func article(_ host: LocalHost, title: String = "Article", paragraphs: [String]) async throws
    -> (item: EntityID, language: String, passages: [ArticleTranslation.Passage], bySource: [String: String])
  {
    let text = (["# " + title] + paragraphs).joined(separator: "\n\n")
    let item = try await host.run(AddTextItem(fileName: "article.md", text: text))
    _ = try await host.run(TranslateArticle(item: item.id))
    let page = await value(host.subscribe(OneItem(item: item.id))) {
      $0.translating == nil && $0.translation?.passages.count == paragraphs.count + 1
    }
    let translation = try #require(page?.translation)
    return (item.id, translation.language, translation.passages, translation.bySource)
  }

  private static func vtt(_ seconds: Int) -> String {
    String(format: "00:%02d:%02d.000", seconds / 60, seconds % 60)
  }
}
