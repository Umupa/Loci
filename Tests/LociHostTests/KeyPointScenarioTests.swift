import Foundation
import LociModel
import Testing

@testable import LociHost

/// K-S2, K-S3: chapters come with the job; key points only when the reader asks, with the choice they made.
struct KeyPointScenarioTests {
  static func video(_ host: LocalHost, _ world: MediaWorld, chapters: [(Double, String)] = []) async throws -> Item {
    world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles, chapters: chapters))
    let item = try await host.run(AddLink(url: Links.url(Links.youtube)))
    #expect(await job(host, item.id, where: isDone) != nil)
    return item
  }

  static func picked(_ host: LocalHost, _ item: EntityID) async -> KeyPointsPage? {
    await value(host.subscribe(ItemKeyPoints(item: item))) { $0.keyPoints != nil && $0.picking == nil }
  }

  @Test func keyPointsArePickedOnlyWhenAsked() async throws {
    try await withMediaHost { host, world in
      let item = try await Self.video(host, world)

      let before = try await host.keyPointsPage(item.id)
      #expect(before.keyPoints == nil)
      #expect(before.picking == nil)
      #expect(!world.agent.requests.contains { $0.hasPrefix("keyPoints") })

      _ = try await host.run(PickKeyPoints(item: item.id, choice: .standard))
      let page = await Self.picked(host, item.id)

      #expect(
        page?.keyPoints?.points.map(\.title) == [
          "All right, so here we are in front of the elephants",
          "the cool thing about these guys is that they have really long trunks",
        ])
      #expect(page?.keyPoints?.choice == .standard)
      #expect(world.agent.requests.filter { $0.hasPrefix("keyPoints") } == ["keyPoints some"])
    }
  }

  @Test func chaptersAreFoundWithTheJobWithoutPickingKeyPoints() async throws {
    try await withMediaHost { host, world in
      let item = try await Self.video(host, world)

      #expect(try await host.run(ReadMediaPage(item: item.id)).outline?.chapters.map(\.title) == ["Agent chapter"])
      #expect(world.agent.requests.contains("outline Me at the zoo"))
    }
  }

  @Test func chaptersFromTheSiteNeedNoAgent() async throws {
    try await withMediaHost { host, world in
      let item = try await Self.video(host, world, chapters: [(0, "Intro"), (5, "Trunks")])

      #expect(try await host.run(ReadMediaPage(item: item.id)).outline?.chapters.map(\.title) == ["Intro", "Trunks"])
      #expect(!world.agent.requests.contains { $0.hasPrefix("outline") })
    }
  }

  @Test func pickingUsesTheChosenModelOrTheOneChaptersAndKeyPointsAreDoneWith() async throws {
    try await withMediaHost { host, world in
      let item = try await Self.video(host, world)
      let chosen = ModelChoice(provider: ModelProviderID(.deepSeek), model: "deepseek-reasoner")

      _ = try await host.run(PickKeyPoints(item: item.id, choice: KeyPointChoice(model: chosen, count: .few)))
      _ = await Self.picked(host, item.id)
      #expect(world.models.all.last == chosen)
      #expect(try await host.keyPointsPage(item.id).model == chosen)

      _ = try await host.run(PickKeyPoints(item: item.id, choice: KeyPointChoice(model: nil, count: .few)))
      #expect(await value(host.subscribe(ItemKeyPoints(item: item.id))) { $0.keyPoints?.choice.model == nil } != nil)
      #expect(world.models.all.last == MediaWorld.model)
    }
  }

  @Test func aChosenModelNoLongerConfiguredFallsBackAndWithoutAnyThereIsNothingToPickWith() async throws {
    try await withMediaHost { host, world in
      let item = try await Self.video(host, world)
      let gone = ModelChoice(provider: ModelProviderID(.kimi), model: "kimi-k3")
      _ = try await host.run(PickKeyPoints(item: item.id, choice: KeyPointChoice(model: gone, count: .few)))
      _ = await Self.picked(host, item.id)
      #expect(world.models.all.last == MediaWorld.model)

      var settings = try await host.readModelSettings().settings
      settings.providers[0].enabled = false
      _ = try await host.saveModelSettings(settings)
      #expect(try await host.keyPointsPage(item.id).model == nil)
      await #expect(throws: HostError.invalidRequest("No model service is configured to pick key points.")) {
        try await host.run(PickKeyPoints(item: item.id, choice: .standard))
      }
    }
  }

  @Test func theLastChoiceIsWhatTheNextPickStartsWith() async throws {
    try await withMediaHost { host, world in
      let item = try await Self.video(host, world)
      #expect(try await host.keyPointsPage(item.id).choice == .standard)
      let choice = KeyPointChoice(model: MediaWorld.model, count: .many)

      _ = try await host.run(PickKeyPoints(item: item.id, choice: choice))
      _ = await Self.picked(host, item.id)

      #expect(try await host.keyPointsPage(item.id).choice == choice)
      #expect(world.agent.requests.contains("keyPoints many"))
    }
  }

  @Test func theReaderIsToldInTheirLanguage() async throws {
    try await withMediaHost(readerLanguage: "zh-Hans") { host, world in
      let item = try await Self.video(host, world)

      _ = try await host.run(PickKeyPoints(item: item.id, choice: .standard))
      _ = await Self.picked(host, item.id)

      #expect(world.agent.keyPointReaders.map(\.language) == ["zh-Hans"])
    }
  }

  @Test func whyTheReaderKeptItReachesThePick() async throws {
    try await withMediaHost { host, world in
      let item = try await Self.video(host, world)
      let kept = try host.store.item(item.id)
      try host.store.save(
        try Item(
          id: kept.id, kind: kept.kind, title: kept.title, authors: kept.authors, source: kept.source,
          language: kept.language, contentHash: kept.contentHash, site: kept.site, published: kept.published,
          why: "For the scheduling interview"))

      _ = try await host.run(PickKeyPoints(item: item.id, choice: .standard))
      _ = await Self.picked(host, item.id)

      #expect(world.agent.keyPointReaders.map(\.why) == ["For the scheduling interview"])
    }
  }

  @Test func aFailureShowsAndTheKeyPointsPickedBeforeStay() async throws {
    try await withMediaHost { host, world in
      let item = try await Self.video(host, world)
      _ = try await host.run(PickKeyPoints(item: item.id, choice: .standard))
      _ = await Self.picked(host, item.id)
      world.agent.fail("the agent ran out of time")

      _ = try await host.run(PickKeyPoints(item: item.id, choice: .standard))
      let failed = await value(host.subscribe(ItemKeyPoints(item: item.id))) {
        if case .failed = $0.picking { true } else { false }
      }

      #expect(failed?.picking == .failed("the agent ran out of time"))
      #expect(failed?.keyPoints?.points.count == 2)
    }
  }

  @Test func anArticlesKeyPointsArePassages() async throws {
    try await withMediaHost { host, world in
      let text = (["# Notes on tail latency"] + (1...6).map { "Paragraph \($0) about queueing." })
        .joined(separator: "\n\n")
      let item = try await host.run(AddTextItem(fileName: "notes.md", text: text))

      _ = try await host.run(PickKeyPoints(item: item.id, choice: .standard))
      let page = await Self.picked(host, item.id)

      #expect(page?.keyPoints?.points.compactMap(\.passage?.number) == [1, 2, 3, 4])
      #expect(page?.keyPoints?.points.last?.passage?.text == "Paragraph 3 about queueing.")
    }
  }

  @Test func aPaperHasNoKeyPoints() async throws {
    try await withMediaHost { host, world in
      let item = try await host.run(AddLink(url: Links.url(Links.paper)))

      await #expect(throws: HostError.self) {
        try await host.run(PickKeyPoints(item: item.id, choice: .standard))
      }
    }
  }
}
