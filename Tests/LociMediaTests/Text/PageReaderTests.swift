import Foundation
import LociMedia
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

  @Test(.timeLimit(.minutes(1)))
  func sourceReadingKeepsTheWholeVisibleDocumentWhenTheArticlePickerMissesMostOfIt() async throws {
    let terms = """
      A message has one or more fields. A sender can combine fields with identical names when the grammar
      permits this. A recipient treats each field as described by the specification for that field.
      """
    let html = """
      <!doctype html>
      <style>.for-print { display: none }</style>
      <nav>Site navigation</nav>
      <main>
        <section>
          <h2>First section of the specification</h2>
          <pre>\(String(repeating: terms + "\n", count: 20))</pre>
        </section>
        <article class="article-content">
          <h2>The featured section</h2>
          <p>\(terms)</p><p>\(terms)</p>
        </article>
        <section>
          <h2>Last section of the specification</h2>
          <pre>\(String(repeating: terms + "\n", count: 20))</pre>
          <p class="for-print">Hidden print instructions</p>
          <p>The final requirement is that the recipient must check the last field.</p>
        </section>
      </main>
      <footer>Site legal notice</footer>
      """
    let markdown = try await sourceMarkdown(html)

    #expect(markdown.contains("## First section of the specification"))
    #expect(markdown.contains("## The featured section"))
    #expect(markdown.contains("## Last section of the specification"))
    #expect(markdown.contains("The final requirement is that the recipient must check the last field."))
    #expect(!markdown.contains("Hidden print instructions"))
    #expect(!markdown.contains("Site navigation"))
    #expect(!markdown.contains("Site legal notice"))
  }

  @Test(.timeLimit(.minutes(1)))
  func sourceReadingKeepsTheExtractedArticleWhenItCoversMostVisibleText() async throws {
    let markdown = try await sourceMarkdown(Self.html)

    #expect(markdown.contains("## Filtering"))
    #expect(markdown.contains("## Scoring"))
    #expect(!markdown.contains("Privacy policy"))
    #expect(!markdown.contains("newsletter"))
  }

  private func sourceMarkdown(_ html: String) async throws -> String {
    let encoded = Data(html.utf8).base64EncodedString()
    let url = try #require(URL(string: "data:text/html;charset=utf-8;base64,\(encoded)"))
    guard case .page(let page) = try await PageReader.source(at: url, timeout: .seconds(20)) else {
      throw FetchError(reason: "Expected HTML, got PDF")
    }
    return page.markdown
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

  @Test(.timeLimit(.minutes(1)))
  func savingTheBrowserMarkupReadsTheArticleWithoutRunningItsScripts() async throws {
    let html = Self.html.replacing(
      "<article>", with: "<article><script>document.querySelector('article').remove()</script>")
    let url = try #require(URL(string: "https://blog.example.com/posts/scheduler"))

    let extraction = try await PageReader.read(.html(html, base: url), timeout: .seconds(10), store: .nonPersistent())

    #expect(extraction.markdown.contains("feasible set"))
    #expect(extraction.markdown.contains("https://blog.example.com/img/flow.png"))
  }
}
