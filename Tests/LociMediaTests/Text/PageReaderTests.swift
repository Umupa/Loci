import Foundation
import Testing

@testable import LociMedia

@MainActor
struct PageReaderTests {
  static let html = """
    <!doctype html>
    <html lang="en"><head>
      <title>How the scheduler picks a node | Example Blog</title>
      <meta name="author" content="Ada Lovelace">
      <meta property="og:site_name" content="Example Blog">
      <meta property="article:published_time" content="2024-03-05T10:00:00Z">
    </head><body>
      <nav><a href="/">Home</a> <a href="/about">About</a> <a href="/subscribe">Subscribe to our newsletter</a></nav>
      <article>
        <h1>How the scheduler picks a node</h1>
        <p>The scheduler filters the nodes that cannot run the pod, then scores the rest. Filtering is a hard \
    constraint; scoring is a preference. Each plugin sees the pod and one node at a time.</p>
        <h2>Filtering</h2>
        <p>A node is filtered out when it lacks the resources the pod requests, when a taint is not tolerated, or \
    when an affinity rule rules it out. What is left is the feasible set.</p>
        <p><img src="/img/flow.png" alt="The flow" width="640" height="360"></p>
        <h2>Scoring</h2>
        <p>Each score plugin gives every feasible node a number from zero to one hundred. The weighted sum decides; \
    ties are broken at random so that load spreads.</p>
      </article>
      <footer>© 2024 Example Inc. All rights reserved. Privacy policy.</footer>
    </body></html>
    """

  @Test(.timeLimit(.minutes(1)))
  func theReadableTextOfAPageComesOutAsMarkdown() async throws {
    let extraction = try await PageReader.read(
      .html(Self.html, base: URL(string: "https://blog.example.com/posts/scheduler")!), timeout: .seconds(20),
      store: .nonPersistent())

    #expect(extraction.title == "How the scheduler picks a node")
    #expect(extraction.author == "Ada Lovelace")
    #expect(extraction.site == "Example Blog")
    #expect(extraction.language == "en")
    #expect(extraction.markdown.contains("## Filtering"))
    #expect(extraction.markdown.contains("feasible set"))
    #expect(extraction.markdown.contains("![The flow](https://blog.example.com/img/flow.png)"))
    #expect(!extraction.markdown.contains("Privacy policy"))
    #expect(!extraction.markdown.contains("newsletter"))
  }

  /// L-S1: a figure that is also the page's cover image stays in the text, where the page shows it. Martin
  /// Fowler's TechnicalDebt sketch is both.
  @Test(.timeLimit(.minutes(1)))
  func aFigureThatIsAlsoTheCoverStaysInTheText() async throws {
    let fixture = try #require(Bundle.module.url(forResource: "Fixtures/technical-debt", withExtension: "html"))
    let html = try String(contentsOf: fixture, encoding: .utf8)

    let extraction = try await PageReader.read(
      .html(html, base: URL(string: "https://martinfowler.com/bliki/TechnicalDebt.html")!), timeout: .seconds(20),
      store: .nonPersistent())

    let markdown = extraction.markdown
    let sketch = try #require(markdown.range(of: "https://martinfowler.com/bliki/images/tech-debt/sketch.png"))
    let interest = try #require(markdown.range(of: "interest paid on the debt"))
    let imagine = try #require(markdown.range(of: "Imagine I have a confusing module structure"))
    #expect(interest.upperBound < sketch.lowerBound)
    #expect(sketch.upperBound < imagine.lowerBound)
  }

  @Test func beingSentToASignInPageIsTold() {
    let asked = URL(string: "https://medium.com/@a/post-1")!
    #expect(PageReader.isSignInPage(URL(string: "https://medium.com/m/signin?redirect=x")!, requested: asked))
    #expect(!PageReader.isSignInPage(asked, requested: asked))
    #expect(
      !PageReader.isSignInPage(
        URL(string: "https://example.com/oauth-explained")!,
        requested: URL(string: "https://example.com/oauth-explained")!))
  }

  @Test func refusedPagesWantASignIn() {
    #expect(PageReader.failure(status: 200) == nil)
    #expect(PageReader.failure(status: 401)?.needsLogin == true)
    #expect(PageReader.failure(status: 404)?.needsLogin == false)
  }
}
