import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// A-S4: a link the address alone does not tell is asked of yt-dlp before it is read as an article.
struct LinkRecognitionTests {
  static let douyin = "https://www.douyin.com/video/6961737553342991651"

  @Test func aLinkYtDlpKnowsBecomesAVideoThatDownloadsAndReads() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Self.douyin, FakeSite(title: "猫和狗", site: "抖音", duration: 42))

      let item = try await host.run(AddLink(url: Links.url(Self.douyin)))

      #expect(await job(host, item.id, where: isDone) != nil)
      let saved = try #require(try await host.run(ListItems()).first)
      #expect(saved.kind == .video(duration: .seconds(42)))
      #expect(saved.title == "猫和狗")
      #expect(try await host.run(ReadPlayback(item: item.id)) == .downloaded)
      #expect(try await host.itemPage(item.id).text == nil)
    }
  }

  @Test func aLinkYtDlpDoesNotKnowIsReadAsAnArticle() async throws {
    try await withMediaHost { host, world in
      let item = try await host.run(AddLink(url: Links.url(Links.article)))

      #expect(await job(host, item.id, where: isDone) != nil)
      let page = try await host.itemPage(item.id)
      #expect(page.item.kind == .article)
      #expect(page.item.title == "Borg, Omega, and Kubernetes")
      #expect(world.programs.calls(with: "--use-extractors").count == 1)
      #expect(world.programs.calls(with: "--print").isEmpty)
    }
  }

  @Test func aSiteYtDlpKnowsWithNoVideoOnThePageIsReadAsAnArticle() async throws {
    try await withMediaHost { host, world in
      world.programs.site(
        Links.article, FakeSite(title: "", refusal: "ERROR: [XiaoHongShu] 6411cf99: No video formats found!"))

      let item = try await host.run(AddLink(url: Links.url(Links.article)))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(try await host.itemPage(item.id).item.kind == .article)
    }
  }

  @Test func aSiteThatWantsCookiesWaitsForASignIn() async throws {
    try await withMediaHost { host, world in
      world.programs.site(
        Self.douyin,
        FakeSite(
          title: "",
          refusal: "ERROR: [Douyin] 6961737553342991651: Fresh cookies (not necessarily logged in) are needed"))

      let item = try await host.run(AddLink(url: Links.url(Self.douyin)))

      #expect(await job(host, item.id, where: state(.waiting(.login(site: "www.douyin.com")))) != nil)
    }
  }

  @Test func withoutYtDlpALinkIsReadAsAnArticleWithoutWaiting() async throws {
    try await withMediaHost(components: []) { host, _ in
      let item = try await host.run(AddLink(url: Links.url(Links.article)))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(try await host.itemPage(item.id).item.kind == .article)
    }
  }
}
