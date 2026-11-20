import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// Translation and outlines by an agent, articles and papers, and the media settings (L-S1, L-S2, L-S14).
struct LibraryWorkTests {
  /// Translations are into the reader's language and are skipped when the transcript is in it already.
  @Test func translationsAreIntoTheReadersLanguage() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken), readerLanguage: "ja") { host, world in
      try world.installModel()
      world.programs.site(Links.bilibili, FakeSite(title: "Scheduling"))

      let item = try await host.run(AddLink(url: Links.url(Links.bilibili)))

      #expect(await job(host, item.id, where: isDone) != nil)
      let page = try await host.run(ReadMediaPage(item: item.id))
      #expect(page.translations.map(\.language) == ["ja"])
      #expect(page.translations.first?.lines.first == "[ja] The scheduler filters nodes.")
      #expect(world.agent.requests == ["translate ja 3", "outline Scheduling"])
    }
  }

  /// O-S5: a long transcript is translated a batch at a time.
  @Test func aTranscriptIsTranslatedAndSavedBatchByBatch() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken), readerLanguage: "ja") { host, world in
      world.programs.site(Links.youtube, FakeSite(title: "Long talk", subtitles: Self.subtitles(130)))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(
        world.agent.requests.filter { $0.hasPrefix("translate") } == [
          "translate ja 60", "translate ja 60", "translate ja 10",
        ])
      #expect(try await host.run(ReadMediaPage(item: item.id)).translations.first?.lines.count == 130)
    }
  }

  /// O-S5: a translation that stopped part way carries on from the first sentence not yet translated.
  @Test func resumingATranslationTranslatesOnlyWhatIsLeft() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken), readerLanguage: "ja") { host, world in
      world.programs.site(Links.youtube, FakeSite(title: "Long talk", subtitles: Self.subtitles(130)))
      world.agent.failBatches(after: 1)

      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))
      let failed =
        await job(host, item.id, where: { if case .failed = $0?.state { true } else { false } }) ?? nil
      #expect(failed?.stage == .translate)
      world.agent.failBatches(after: nil)
      _ = try await host.run(RetryJob(item: item.id))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(
        world.agent.requests.filter { $0.hasPrefix("translate") } == [
          "translate ja 60", "translate ja 60", "translate ja 60", "translate ja 10",
        ])
      let lines = try await host.run(ReadMediaPage(item: item.id)).translations.first?.lines
      #expect(lines?.count == 130)
      #expect(lines?.last == "[ja] Sentence 129.")
    }
  }

  static func subtitles(_ count: Int) -> String {
    "WEBVTT\n\n"
      + (0..<count).map { index in
        let start = String(format: "00:%02d:%02d.000", index / 60, index % 60)
        let end = String(format: "00:%02d:%02d.900", index / 60, index % 60)
        return "\(start) --> \(end)\nSentence \(index).\n"
      }.joined(separator: "\n")
  }

  @Test func aTranscriptAlreadyInTheReadersLanguageIsNotTranslated() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken), readerLanguage: "en-GB") { host, world in
      try world.installModel()
      world.programs.site(Links.bilibili, FakeSite(title: "Scheduling"))

      let item = try await host.run(AddLink(url: Links.url(Links.bilibili)))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(try await host.run(ReadMediaPage(item: item.id)).translations.isEmpty)
      #expect(world.agent.requests == ["outline Scheduling"])
    }
  }

  /// Without an agent the transcript is still there, and the job waits for one.
  @Test func withoutAnAgentTranslationWaits() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken), agent: false) { host, world in
      try world.installModel()
      world.programs.site(Links.bilibili, FakeSite(title: "Scheduling"))

      let item = try await host.run(AddLink(url: Links.url(Links.bilibili)))

      let waiting = await job(host, item.id, where: state(.waiting(.agent)))
      #expect(waiting??.stage == .translate)
      #expect(try await host.run(ReadMediaPage(item: item.id)).transcript?.segments.count == 3)
    }
  }

  /// L-S1: an article's text and pictures are kept beside it, to read offline.
  @Test func anArticleLinkKeepsItsTextAndPictures() async throws {
    try await withMediaHost { host, _ in
      let item = try await host.run(AddLink(url: Links.url(Links.article)))
      let page = host.subscribe(OneItem(item: item.id))

      #expect(item.kind == .article)
      let read = await value(page) { $0.text != nil && $0.item.site != nil }
      #expect(read?.item.title == "Borg, Omega, and Kubernetes")
      #expect(read?.item.site == "ACM Queue")
      #expect(read?.text?.contains("![](images/figure-1.png)") == true)
      #expect(try await host.run(ReadItemImage(item: item.id, name: "images/figure-1.png")) == Data("png".utf8))
      #expect(try await host.run(ReadItemImage(item: item.id, name: "figure-1.png")) == Data("png".utf8))
      await #expect(throws: HostError.self) {
        try await host.run(ReadItemImage(item: item.id, name: "../item.json"))
      }
    }
  }

  /// L-S2: a paper is read as its PDF.
  @Test func aPaperLinkKeepsItsPDF() async throws {
    try await withMediaHost { host, _ in
      let item = try await host.run(AddLink(url: Links.url(Links.paper)))

      #expect(item.kind == .paper)
      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(try await host.run(ReadItemPDF(item: item.id)) == Data("%PDF-1.7".utf8))
      let page = try await host.itemPage(item.id)
      #expect(page.text == nil)
      #expect(page.item.title == "Large-scale cluster management at Google with Borg")
    }
  }

  @Test func anArticleBehindASignInWaitsForOne() async throws {
    try await withMediaHost { host, _ in
      let item = try await host.run(AddLink(url: URL(string: "https://example.com/members/post")!))

      #expect(await job(host, item.id, where: state(.waiting(.login(site: "example.com")))) != nil)
    }
  }

  @Test func aReadableBrowserPageIsSavedEvenWhenFetchingItsLinkWouldAskForSignIn() async throws {
    try await withMediaHost { host, _ in
      let url = try #require(URL(string: "https://example.com/members/post"))
      let item = try await host.run(AddLink(url: url, articleHTML: "<article>Body already in the browser.</article>"))

      #expect(await job(host, item.id, where: isDone) != nil)
      let page = try await host.itemPage(item.id)
      #expect(page.item.source == url)
      #expect(page.text?.contains("Body already in the browser.") == true)
    }
  }

  @Test func withoutAFetcherAnArticleFailsSayingSo() async throws {
    try await withMediaHost(text: false) { host, _ in
      let item = try await host.run(AddLink(url: Links.url(Links.article)))

      let failed = await job(host, item.id) { job in
        if case .failed = job?.state { true } else { false }
      }
      #expect(failed != nil)
    }
  }

  /// L-S14: components, their installs, the speech models and the sign-in choice, as the settings show them.
  @Test func theMediaSettingsShowComponentsModelsAndProgress() async throws {
    try await withMediaHost(components: [.ytDlp]) { host, world in
      let settings = host.subscribe(MediaSettings())
      let first = await value(settings) { _ in true }
      #expect(first?.components.map(\.component) == Component.allCases)
      guard case .system(let path, let version) = first?.components.first?.installation else {
        Issue.record("expected yt-dlp from the system")
        return
      }
      #expect(path.hasSuffix(".bin/yt-dlp"))
      #expect(version == "2026.10.26")
      #expect(first?.components.dropFirst().map(\.installation) == [.missing, .missing])
      #expect(first?.speechModel == .recommended)
      #expect(first?.speechModels.allSatisfy { $0.state == .absent } == true)

      await world.network.downloads.close()
      _ = try await host.run(DownloadSpeechModel(.base))
      let downloading = await value(settings) { setup in
        setup.speechModels.contains {
          $0 == SpeechModelStatus(model: .base, state: .transferring(.running(Fraction(0.5))))
        }
      }
      #expect(downloading != nil)
      await world.network.downloads.open()
      #expect(await value(settings) { $0.speechModels.contains { $0 == .init(model: .base, state: .ready) } } != nil)

      _ = try await host.run(InstallComponent(.ffmpeg))
      let installed = await value(settings) { $0.components[1].installation != .missing && $0.componentWork.isEmpty }
      #expect(installed?.components[1].installation == .managed(version: "9.0.1"))

      #expect(try await host.run(SetSpeechModel(.base)).speechModel == .base)
      _ = try await host.run(DeleteSpeechModel(.base))
      #expect(await value(settings) { $0.speechModels.allSatisfy { $0.state == .absent } } != nil)
    }
  }

  @Test func detectingAgainFindsAComponentInstalledSince() async throws {
    try await withMediaHost(components: []) { host, world in
      #expect(try await host.run(DetectComponents(again: false)).first?.installation == .missing)
      try world.install([.ytDlp])

      #expect(try await host.run(DetectComponents(again: false)).first?.installation == .missing)
      let again = try await host.run(DetectComponents(again: true))
      #expect(again.first?.installation != .missing)
    }
  }
}
