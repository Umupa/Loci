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

  @Test func aPageWithALongBodyOfTextReportsAnArticle() async throws {
    let paragraph = "<p>" + String(repeating: "Pingora is a proxy written in Rust. ", count: 20) + "</p>"
    let facts = try await Self.facts(
      of: "<html><body><article>\(String(repeating: paragraph, count: 4))</article></body></html>",
      at: "https://blog.cloudflare.com/pingora")
    #expect(facts.hasArticle)
    #expect(facts.videos.isEmpty)
  }
}
