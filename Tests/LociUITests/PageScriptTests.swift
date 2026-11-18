import Foundation
import Testing

@testable import LociUI

/// The page script in a real web view, on pages written here, so no network is touched.
@MainActor
@Suite(.serialized)
struct PageScriptTests {
  static func facts(of html: String, at address: String) async throws -> PageFacts {
    let session = BrowserSession()
    let url = try #require(URL(string: address))
    session.webView.loadHTMLString(html, baseURL: url)
    let deadline = ContinuousClock.now + .seconds(10)
    while ContinuousClock.now < deadline {
      if session.facts != PageFacts() { return session.facts }
      try await Task.sleep(for: .milliseconds(100))
    }
    return session.facts
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

  /// L-S15: a playlist's "Play all" and "Shuffle" link to videos in it, but are controls, not videos.
  @Test func aPlaylistPageReportsItsVideosAndNotItsPlayButtons() async throws {
    let header = """
      <div class="metadata-action-bar">
        <yt-button-shape><a class="yt-spec-button-shape-next" href="/watch?v=a1&list=PL1&pp=sAgC" aria-label="全部播放">全部播放</a></yt-button-shape>
        <yt-button-shape><a class="yt-spec-button-shape-next" href="/watch?v=a3&list=PL1&start_radio=1" aria-label="随机播放">随机播放</a></yt-button-shape>
      </div>
      <a href="/watch?v=a9&list=PL1&start_radio=1">随机播放</a>
      """
    let entries = ["First talk", "Second talk", "Third talk"].enumerated().map { index, title in
      """
      <ytd-playlist-video-renderer>
        <a id="thumbnail" href="/watch?v=a\(index + 1)&list=PL1&index=\(index + 1)"><img src="https://i.ytimg.com/vi/a\(index + 1)/hq.jpg"><div class="badge-shape-wiz__text">4:0\(index)</div></a>
        <a id="video-title" href="/watch?v=a\(index + 1)&list=PL1&index=\(index + 1)" title="\(title)">\(title)</a>
      </ytd-playlist-video-renderer>
      """
    }
    let facts = try await Self.facts(
      of: "<html><body>\(header)\(entries.joined())</body></html>",
      at: "https://www.youtube.com/playlist?list=PL1")
    #expect(facts.videos.map(\.title) == ["First talk", "Second talk", "Third talk"])
    #expect(facts.videos.map(\.duration) == ["4:00", "4:01", "4:02"])
  }

  @Test func aPageWithALongBodyOfTextReportsAnArticle() async throws {
    let paragraph = "<p>" + String(repeating: "Pingora is a proxy written in Rust. ", count: 20) + "</p>"
    let facts = try await Self.facts(
      of: "<html><body><article>\(String(repeating: paragraph, count: 4))</article></body></html>",
      at: "https://blog.cloudflare.com/pingora")
    #expect(facts.hasArticle)
    #expect(facts.videos.isEmpty)
  }
}
