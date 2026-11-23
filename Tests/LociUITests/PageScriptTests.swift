import Foundation
import Testing

@testable import LociUI

/// The page script in a real web view, on pages written here, so no network is touched.
@MainActor
@Suite(.serialized, .onStage)
struct PageScriptTests {
  static func facts(of html: String, at address: String) async throws -> PageFacts {
    let session = BrowserSession()
    let tab = session.current
    let url = try #require(URL(string: address))
    session.webView(for: tab).loadHTMLString(html, baseURL: url)
    let deadline = ContinuousClock.now + .seconds(60)
    var last = PageFacts()
    var unchanged = 0
    while ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(100))
      unchanged = tab.facts == last ? unchanged + 1 : 0
      last = tab.facts
      if last != PageFacts() && unchanged >= 5 { return last }
    }
    return tab.facts
  }

  @Test func aChannelPageReportsEachVideoOnceWithItsTitleAndLength() async throws {
    let cards = (1...3).map { index in
      """
      <a href="/watch?v=v\(index)&t=10s"><img src="https://i.ytimg.com/vi/v\(index)/hq.jpg"><span class="duration">3\(index):12</span></a>
      <a href="/watch?v=v\(index)" title="Talk number \(index)">Talk number \(index)</a>
      """
    }
    let facts = try await Self.facts(
      of: "<html><body>\(cards.joined())<a href=\"/about\">About</a></body></html>",
      at: "https://www.youtube.com/@cncf/videos")
    #expect(facts.videos.map(\.title) == ["Talk number 1", "Talk number 2", "Talk number 3"])
    #expect(facts.videos.first?.url.absoluteString == "https://www.youtube.com/watch?v=v1")
    #expect(facts.videos.first?.duration == "31:12")
    #expect(!facts.hasArticle)
  }

  /// A YouTube page as the built-in browser saw it, with its scripts taken out.
  static func youtube(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/youtube-\(name)", withExtension: "html"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// L-S15: a real channel page. Its video cards carry classes that mention a menu button, and the title link
  /// is named with the length spoken after it; neither may cost a video or spoil its title.
  @Test func aRealChannelPageReportsItsVideos() async throws {
    let facts = try await Self.facts(
      of: try Self.youtube("channel"), at: "https://www.youtube.com/@RickAstleyYT/videos")

    #expect(
      facts.videos.map(\.title) == [
        "Rick Astley - Angels On My Side (Live at The O2, London, April 2026)",
        "Rick Astley - Dance (Live at The O2, London, April 2026)",
        "Rick Astley - Keep Singing (Live at The O2, London, April 2026)",
      ])
    #expect(facts.videos.map(\.duration) == ["3:51", "3:54", "4:08"])
    #expect(facts.videos.allSatisfy { $0.thumbnail != nil })
  }

  /// L-S15: a real playlist page reports its videos, and not "Play all", "Shuffle" or the playlist's own title,
  /// which link to a video in it too.
  @Test func aRealPlaylistPageReportsItsVideosAndNotItsControls() async throws {
    let facts = try await Self.facts(
      of: try Self.youtube("playlist"), at: "https://www.youtube.com/playlist?list=UUuAXFkgsw1L7xaCfnd5JJOw")

    #expect(facts.videos.count == 10)
    #expect(facts.videos.first?.title.hasPrefix("Recording an audiobook is a lot harder than you think") == true)
    #expect(!facts.videos.contains { ["全部播放", "随机播放"].contains($0.title) || $0.title.hasPrefix("来自") })
    #expect(facts.videos.allSatisfy { $0.duration != nil })
  }

  @Test func aPageWithALongBodyOfTextReportsAnArticle() async throws {
    let paragraph = "<p>" + String(repeating: "Pingora is a proxy written in Rust. ", count: 20) + "</p>"
    let facts = try await Self.facts(
      of: "<html><body><article>\(String(repeating: paragraph, count: 4))</article></body></html>",
      at: "https://blog.cloudflare.com/pingora")
    #expect(facts.hasArticle)
    #expect(facts.videos.isEmpty)
  }

  /// A hand-written page such as raft.github.io keeps its text straight in the body, with no article around it.
  @Test func aLongBodyOfTextWithNoArticleAroundItStillReportsAnArticle() async throws {
    let paragraph = "<p>" + String(repeating: "Raft is a consensus algorithm. ", count: 20) + "</p>"
    let facts = try await Self.facts(
      of: "<html><body><h1>Raft</h1>\(String(repeating: paragraph, count: 4))</body></html>",
      at: "https://raft.github.io/")
    #expect(facts.hasArticle)
  }

  @Test func aPageOfShortLinesIsNoArticle() async throws {
    let line = "<p>Sign in to continue.</p>"
    let facts = try await Self.facts(
      of: "<html><body>\(String(repeating: line, count: 10))</body></html>", at: "https://example.com/")
    #expect(!facts.hasArticle)
  }

  /// H-S7: papers and PDFs a page links to are reported once each, named by their link, and the page's own
  /// address is not.
  @Test func aPageReportsThePapersItLinksTo() async throws {
    let facts = try await Self.facts(
      of: """
        <html><body>
        <a href="/raft.pdf">In Search of an Understandable Consensus Algorithm</a>
        <a href="/raft.pdf#page=3">section 5</a>
        <a href="https://arxiv.org/abs/1706.03762">Attention Is All You Need</a>
        <a href="https://arxiv.org/list/cs.DC/recent">Recent</a>
        <a href="/">Home</a>
        </body></html>
        """,
      at: "https://raft.github.io/")
    #expect(facts.papers.map(\.title) == ["In Search of an Understandable Consensus Algorithm", "Attention Is All You Need"])
    #expect(facts.papers.first?.url.absoluteString == "https://raft.github.io/raft.pdf")
  }

  /// H-S7: a talks page names its links only "YouTube" and "PDF"; each is named by the entry it sits in, and a
  /// video with no picture on the page gets YouTube's own.
  @Test func linksNamedOnlyByTheirSiteTakeTheNameOfTheirEntry() async throws {
    let entry = """
      <li>Talk on Raft at <a href="https://cs.illinois.edu/">CS@Illinois</a> by John Ousterhout, August 2016:
        <table><tr><td>Video</td><td><a href="https://youtu.be/vYp4LYbnnW8">YouTube</a></td></tr>
        <tr><td>Slides</td><td><a href="slides/uiuc2016.pdf">PDF</a></td></tr></table></li>
      """
    let facts = try await Self.facts(of: "<html><body><ul>\(entry)</ul></body></html>", at: "https://raft.github.io/")
    let name = "Talk on Raft at CS@Illinois by John Ousterhout, August 2016"
    #expect(facts.videos.map(\.title) == [name])
    #expect(facts.videos.first?.thumbnail?.absoluteString == "https://i.ytimg.com/vi/vYp4LYbnnW8/mqdefault.jpg")
    #expect(facts.papers.map(\.title) == [name])
  }
}
