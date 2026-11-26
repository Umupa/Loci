import Foundation
import LociModel
import Testing

@testable import LociMedia

/// DS-S4, DS-S5: a page a source reads, as no one or signed in, sends nothing but the GETs the app makes:
/// each redirect is looked at before it is followed, the sign-in goes only to its own site, and nothing on
/// the page itself reaches the network.
@Suite(.timeLimit(.minutes(1)))
struct SourcePagesTests {
  static func site() async throws -> ControlledSite { try await ControlledSite.start() }

  static func page(_ port: UInt16) -> String {
    """
    <!doctype html><html><head><title>行情</title>
    <link rel="stylesheet" href="/style.css"><script src="/app.js"></script></head>
    <body><main><h1>纳指 ETF</h1><p>溢价 3.21%</p>
    <img src="/pixel.png"><iframe src="/frame"></iframe>
    <form method="post" action="/form"><input name="a"></form>
    <script>
      fetch("/fetch", { method: "POST", body: "x" });
      const xhr = new XMLHttpRequest(); xhr.open("DELETE", "/xhr"); xhr.send();
      new WebSocket("ws://127.0.0.1:\(port)/socket");
      new Worker("/worker.js");
      navigator.sendBeacon("/beacon", "x");
      document.forms[0].submit();
    </script></main></body></html>
    """
  }

  @Test func aPageSendsOnlyTheAppsGetAndNothingOfItsOwn() async throws {
    let site = try await Self.site()
    defer { site.stop() }
    site.set("/page", .init(body: Self.page(site.port)))

    let text = try await SourcePages(hops: HopNetwork()).read(site.url("/page"))

    #expect(text.contains("溢价 3.21%"))
    try await Task.sleep(for: .milliseconds(300))
    #expect(site.requests == [ControlledSite.Request(method: "GET", path: "/page", cookie: nil)])
  }

  @Test func aRedirectIsFollowedAsAGetAndTheSignInStaysOnItsSite() async throws {
    let site = try await Self.site()
    defer { site.stop() }
    site.set("/start", .init(status: 307, headers: ["Location": "/moved"]))
    site.set(
      "/moved", .init(status: 302, headers: ["Location": site.url("/elsewhere", host: "localhost").absoluteString]))
    site.set("/elsewhere", .init(body: "<main><p>到了</p></main>"))
    let cookie = try #require(
      HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "session", .value: "secret"]))

    let text = try await SourcePages(hops: HopNetwork()).read(
      site.url("/start"), cookies: [cookie], domains: ["127.0.0.1"])

    #expect(text.contains("到了"))
    #expect(
      site.requests == [
        .init(method: "GET", path: "/start", cookie: "session=secret"),
        .init(method: "GET", path: "/moved", cookie: "session=secret"),
        .init(method: "GET", path: "/elsewhere", cookie: nil),
      ])
  }

  @Test func aRedirectToSomethingNotOnTheWebOrOneTooManyIsRefused() async throws {
    let site = try await Self.site()
    defer { site.stop() }
    site.set("/file", .init(status: 302, headers: ["Location": "file:///etc/hosts"]))
    site.set("/loop", .init(status: 302, headers: ["Location": "/loop"]))
    let pages = SourcePages(hops: HopNetwork())

    await #expect(throws: FetchError.self) { try await pages.read(site.url("/file")) }
    await #expect(throws: FetchError.self) { try await pages.read(site.url("/loop")) }
    #expect(site.requests.count { $0.path == "/loop" } == SourcePages.mostHops + 1)
  }

  @Test func whatIsNotAPageIsGivenAsItCame() async throws {
    let site = try await Self.site()
    defer { site.stop() }
    site.set("/api", .init(headers: ["Content-Type": "application/json"], body: #"{"price": 1.873}"#))

    #expect(try await SourcePages(hops: HopNetwork()).read(site.url("/api")) == #"{"price": 1.873}"#)
  }
}
