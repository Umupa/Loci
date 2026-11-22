import Foundation
import LociMedia
import LociModel
import LociStore
import Synchronization
import Testing

@testable import LociHost

struct ModelServiceTests {
  @Test func onlyPreferencesGoToTheDataFolderAndTheKeyCanBeRemoved() async throws {
    try await withModelHost { host, world, network, keys in
      let service = try #require(ModelService(provider: .openAI, model: "fixture"))
      let settings = ModelSettings(service: service, translation: TranslationSettings(language: "ja", smart: true))
      #expect(try await host.readModelSettings().hasKey == false)
      try await host.testModelService(service, key: "temporary-key")
      #expect(keys.key(for: service) == nil)

      let saved = try await host.saveModelSettings(settings, key: .replace("saved-key"))
      #expect(saved.hasKey)
      #expect(try world.place.store.modelSettings() == settings)
      let text = try String(
        contentsOf: world.place.root.appending(path: "model-settings.json"), encoding: .utf8)
      #expect(!text.contains("saved-key"))
      try await host.testModelService(service, key: nil)
      #expect(await network.keys == ["Bearer temporary-key", "Bearer saved-key"])
      #expect(try await host.run(ReadImportChoice()).translation?.language == "ja")

      let changed = try #require(
        ModelService(provider: .compatible, model: "fixture", baseURL: URL(string: "https://models.example.test/v1")))
      #expect(try await host.saveModelSettings(ModelSettings(service: changed), key: .keep).hasKey == false)
      #expect(try await host.saveModelSettings(settings, key: .keep).hasKey)
      #expect(try await host.saveModelSettings(settings, key: .remove).hasKey == false)
      #expect(keys.key(for: service) == nil)
    }
  }

  @Test func anArticleFinishesItsTranslationStageWithConcurrentBatchesInOriginalOrder() async throws {
    try await withModelHost { host, world, network, _ in
      let settings = try modelSettings()
      _ = try await host.saveModelSettings(settings, key: .replace("test-key"))
      let paragraphs = (1...81).map { "This is distinct paragraph \($0)." }

      let text = (["# Article"] + paragraphs).joined(separator: "\n\n")
      let choice = ImportChoice(
        keeping: .online, quality: .audio, siteSubtitles: false, recognition: nil,
        translation: .init(language: "fr", runtime: Runtime(provider: .codex)))

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
      #expect(world.runtimes.all.isEmpty)

      _ = try await host.saveModelSettings(settings, key: .remove)
      _ = try await article(host, paragraphs: ["This stays on the Runtime."])
      #expect(world.runtimes.all == [Runtime(provider: .codex)])
    }
  }

  @Test func overlappingArticlesShareTranslationsAndCacheSizeAndClearAreVisible() async throws {
    try await withModelHost { host, _, network, _ in
      _ = try await host.saveModelSettings(modelSettings(), key: .replace("test-key"))
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
      var settings = try modelSettings()
      _ = try await host.saveModelSettings(settings, key: .replace("test-key"))
      _ = try await article(host, paragraphs: [paragraph])

      settings.translation.language = "ja"
      _ = try await host.saveModelSettings(settings, key: .keep)
      #expect(try await article(host, paragraphs: [paragraph]).language == "ja")

      settings.service = ModelService(provider: .openAI, model: "different-model")
      _ = try await host.saveModelSettings(settings, key: .keep)
      _ = try await article(host, paragraphs: [paragraph])

      settings.translation.articlePrompt = "Write naturally in {{language}}."
      _ = try await host.saveModelSettings(settings, key: .keep)
      _ = try await article(host, paragraphs: [paragraph])

      settings.translation.smart = true
      _ = try await host.saveModelSettings(settings, key: .keep)
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
      var settings = try modelSettings()
      settings.translation.transcriptPrompt = "Translate speech into {{language}}."
      settings.translation.articlePrompt = "Only for articles."
      settings.translation.smart = true
      _ = try await host.saveModelSettings(settings, key: .replace("test-key"))
      let lines = (0..<122).map { "Sentence \($0)." }
      let cues = lines.enumerated().map { index, line in
        "\(Self.vtt(index * 2)) --> \(Self.vtt(index * 2 + 1))\n\(line)\n\n"
      }.joined()
      world.programs.site(Links.youtube, FakeSite(title: "A video", subtitles: "WEBVTT\n\n" + cues))
      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))
      _ = try #require(await job(host, item.id, where: isDone))
      let media = try await host.run(ReadMediaPage(item: item.id))
      #expect(media.translations.first?.lines == lines.map { "translated " + $0 })
      #expect(media.outline?.chapters.map(\.title) == ["Model chapter"])
      #expect(await network.peak == 2)

      _ = try await host.run(PickKeyPoints(item: item.id, choice: KeyPointChoice(runtime: nil, count: .few)))
      let points = await KeyPointScenarioTests.picked(host, item.id)
      #expect(points?.keyPoints?.points.map(\.title) == ["First", "Second", "Third"])
      #expect(world.agent.requests.isEmpty)
      let prompts = await network.prompts
      #expect(prompts.count { $0.contains("Translate speech into fr.") && $0.contains("Sentence 121.") } == 3)
      #expect(prompts.allSatisfy { !$0.contains("Only for articles.") })
    }
  }

  private func withModelHost(
    _ body: (LocalHost, MediaWorld, TranslationModelNetwork, MemoryModelKeys) async throws -> Void
  ) async throws {
    let world = MediaWorld()
    defer { world.place.remove() }
    try world.install()
    let media = world.environment(transcriber: FakeTranscriber([])).media
    let network = TranslationModelNetwork()
    let keys = MemoryModelKeys()
    let environment = HostEnvironment(
      newID: { world.world.nextID() }, now: { TestWorld.instant }, defaultRuntime: Runtime(provider: .codex),
      discard: .permanently, agents: { _ in nil }, media: media,
      modelKeys: keys, modelClient: ModelClient(network: network), modelParallelism: 2)
    let host = try await LocalHost.start(
      root: world.place.root, database: world.place.database, environment: environment)
    do {
      try await body(host, world, network, keys)
    } catch {
      await host.close()
      throw error
    }
    await host.close()
  }

  private func modelSettings() throws -> ModelSettings {
    let service = try #require(ModelService(provider: .openAI, model: "fixture"))
    return ModelSettings(service: service, translation: TranslationSettings(language: "fr"))
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

final class MemoryModelKeys: ModelKeyStore {
  private let stored = Mutex<[URL: String]>([:])

  func key(for service: ModelService) -> String? { stored.withLock { $0[service.endpoint] } }
  func setKey(_ key: String?, for service: ModelService) { stored.withLock { $0[service.endpoint] = key } }
}

private actor TranslationModelNetwork: Network {
  let batches = Latch(open: true)
  private var active = 0
  private(set) var peak = 0
  private(set) var keys: [String] = []
  private(set) var prompts: [String] = []
  private(set) var translationInputs: [[String]] = []

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil),
      let body = request.httpBody,
      let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let prompt = (payload["messages"] as? [[String: String]])?.first?["content"]
    else { throw FetchError(reason: "invalid request") }
    keys.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
    prompts.append(prompt)
    let reply: String
    if let start = prompt.range(of: "The input:\n", options: .backwards),
      let inputs = try? JSONDecoder().decode([String: [String]].self, from: Data(prompt[start.upperBound...].utf8)),
      let lines = inputs["lines"]
    {
      translationInputs.append(lines)
      active += 1
      peak = max(peak, active)
      defer { active -= 1 }
      await batches.wait()
      try? await Task.sleep(for: lines.first?.hasPrefix("#") == true ? .milliseconds(110) : .milliseconds(45))
      let json = try? JSONEncoder().encode(["lines": lines.map { "translated " + $0 }])
      reply = String(decoding: json ?? Data(), as: UTF8.self)
    } else if prompt.contains(#"{"chapters":"#) {
      reply = #"{"chapters":[{"start":0,"title":"Model chapter"}]}"#
    } else if prompt.contains(#"{"keyPoints":"#) {
      reply =
        #"{"keyPoints":[{"start":0,"end":1,"title":"First","reason":"A"},"#
        + #"{"start":2,"end":3,"title":"Second","reason":"B"},{"start":4,"end":5,"title":"Third","reason":"C"}]}"#
    } else {
      reply = "OK"
    }
    do {
      let data = try JSONEncoder().encode(["choices": [["message": ["content": reply]]]])
      return (data, response)
    } catch {
      throw FetchError(reason: "could not encode fake reply")
    }
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "no downloads")
  }
}
