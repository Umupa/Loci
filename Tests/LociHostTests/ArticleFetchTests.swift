import Foundation
import LociHost
import LociMedia
import LociModel
import Testing

struct ArticleFetchTests {
  @Test func theTitleAndCoverArriveWhileTheArticleIsStillBeingRead() async throws {
    let body = Latch(open: false)
    let world = MediaWorld()
    defer { world.place.remove() }
    let host = try await world.start(fetcher: HeldArticle(body: body))
    let item = try await host.run(AddLink(url: Links.url(Links.article)))
    let extract = await job(host, item.id, where: isRunning(.extract))
    #expect(extract??.stages == [.fetchPage, .extract, .findCover])
    #expect(try await host.itemPage(item.id).item.title == "The title from the page")
    #expect(try await host.itemPage(item.id).text == nil)
    #expect(try await host.run(ReadCover(item: item.id)) == FakeNetwork.cover)

    await body.open()
    #expect(await value(host.subscribe(OneItem(item: item.id))) { $0.text == "The extracted body." } != nil)
    await host.close()
  }

  @Test func retryingAFailedPageFetchGetsTheArticle() async throws {
    let failures = PageFailures()
    let world = MediaWorld()
    defer { world.place.remove() }
    let host = try await world.start(fetcher: HeldArticle(failures: failures))
    let item = try await host.run(AddLink(url: Links.url(Links.article)))
    let failed = await job(host, item.id) {
      if case .failed = $0?.state { true } else { false }
    }
    #expect(failed??.stage == .fetchPage)
    await failures.allow()
    _ = try await host.run(RetryJob(item: item.id))
    #expect(await value(host.subscribe(OneItem(item: item.id))) { $0.text == "The extracted body." } != nil)
    await host.close()
  }

  @Test func olderItemsAreGivenCoversOnceAndManualCoversSurvive() async throws {
    let world = MediaWorld()
    defer { world.place.remove() }
    try world.install()
    let source = Links.url(Links.youtube)
    world.programs.site(Links.youtube, FakeSite(title: "Already in the library"))
    let old = try Item(id: world.world.nextID(), kind: .video(duration: nil), title: "Old", source: source)
    let manual = try Item(
      id: world.world.nextID(), kind: .video(duration: nil), title: "Manual",
      source: Links.url("https://www.youtube.com/watch?v=custom"))
    try world.place.store.addPending(old)
    try world.place.store.addPending(manual)
    let chosen = Data("chosen picture".utf8)
    try world.place.store.saveCover(chosen, extension: "png", of: manual.id)

    let host = try await world.start()
    #expect(await value(host.subscribe(ItemCover(item: old.id))) { $0 == FakeNetwork.cover } != nil)
    #expect(try await host.run(ReadCover(item: manual.id)) == chosen)
    let limit = ContinuousClock.now + .seconds(5)
    while !world.place.store.didBackfillCovers, ContinuousClock.now < limit {
      try await Task.sleep(for: .milliseconds(10))
    }
    await host.close()
    #expect(world.place.store.didBackfillCovers)
    #expect(world.programs.calls(with: "-J").count == 1)

    let cover = try #require(try world.place.store.coverFile(of: old.id))
    try FileManager.default.removeItem(at: cover)
    let reopened = try await world.start()
    #expect(await value(reopened.subscribe(HealthReport())) { $0.database == .ready } != nil)
    await reopened.close()
    #expect(try world.place.store.cover(of: old.id) == nil)
    #expect(world.programs.calls(with: "-J").count == 1)
  }

  @Test func aRequestedTranslationAppearsAfterTheArticleStages() async throws {
    let body = Latch(open: false)
    let world = MediaWorld()
    defer { world.place.remove() }
    let host = try await world.start(fetcher: HeldArticle(body: body))
    let choice = ImportChoice(
      keeping: .online, quality: .audio, siteSubtitles: false, recognition: nil,
      translation: .init(language: "zh-Hans", runtime: Runtime(provider: .codex)))
    let item = try await host.run(AddLink(url: Links.url(Links.article), choice: choice))
    let extract = await job(host, item.id, where: isRunning(.extract))
    #expect(extract??.stages == [.fetchPage, .extract, .findCover, .translate])
    await body.open()
    #expect(await value(host.subscribe(OneItem(item: item.id))) { $0.translation?.language == "zh-Hans" } != nil)
    await host.close()
  }
}

private actor PageFailures {
  private(set) var failing = true

  func allow() { failing = false }
}

private struct HeldArticle: TextFetching {
  var body = Latch(open: true)
  var failures: PageFailures?

  func articlePage(at url: URL, html: String?) async throws(FetchError) -> ArticlePage {
    if let failures, await failures.failing { throw FetchError(reason: "Could not reach the page.") }
    let image = Links.url("https://img.example.com/cover.jpg")
    return ArticlePage(
      preview: LinkPreview(url: url, title: "The title from the page", site: "ACM Queue", summary: nil, image: image),
      coverImages: [image]
    ) { () async throws(FetchError) in
      await body.wait()
      return FetchedArticle(
        title: "The title from the page", authors: [], site: "ACM Queue", published: nil, language: "en",
        markdown: "The extracted body.", images: [])
    }
  }

  func paper(at url: URL) async throws(FetchError) -> FetchedPaper {
    throw FetchError(reason: "No paper at this address.")
  }
}
