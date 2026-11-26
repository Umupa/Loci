import Foundation
import Testing

@testable import LociMedia

@MainActor
struct PageTidyingTests {
  static let base = URL(string: "https://blog.example.com/posts/sandbox")!

  static func page(_ body: String) -> String {
    let words = String(
      repeating: "The sandbox limits what a command can reach while it runs on the machine it was started on. ",
      count: 6)
    return """
      <!doctype html><html lang="en"><head><title>Inside the sandbox</title></head><body>
      <nav><a href="/">Home</a></nav>
      <article><h1>Inside the sandbox</h1>
      <p>\(words)</p>
      \(body)
      <p>\(words)</p>
      </article></body></html>
      """
  }

  static func markdown(_ body: String) async throws -> String {
    try await PageReader.read(.html(page(body), base: base), timeout: .seconds(20), as: .anonymous).markdown
  }

  @Test(.timeLimit(.minutes(1)))
  func aDiagramDrawnInThePageBecomesAPicture() async throws {
    let markdown = try await Self.markdown(
      """
      <figure class="figure diagram wide">
        <svg viewBox="0 0 720 380" xmlns="http://www.w3.org/2000/svg"><title>The gateway records ranges</title>
          <rect x="24" y="48" width="166" height="64" rx="8" fill="none" stroke="currentColor"></rect>
          <text x="38" y="74" fill="currentColor">program</text>
          <path d="M190 80 H242" fill="none" stroke="currentColor"></path>
        </svg>
        <figcaption>The gateway records requested ranges for an image.</figcaption>
      </figure>
      """)

    #expect(!markdown.contains("<svg"))
    #expect(!markdown.contains("<rect"))
    let drawn = try #require(markdown.firstMatch(of: /!\[[^\]]*\]\(data:image\/svg\+xml;base64,([A-Za-z0-9+\/=]+)\)/))
    let data = try #require(Data(base64Encoded: String(drawn.output.1)))
    let svg = String(decoding: data, as: UTF8.self)
    #expect(svg.contains("program"))
    #expect(!svg.contains("currentColor"))
    #expect(markdown.contains("The gateway records requested ranges for an image."))
  }

  @Test(.timeLimit(.minutes(1)))
  func aSourceReadForTheCompanionCarriesNoPictureData() async throws {
    let html = Self.page(
      """
      <figure><svg viewBox="0 0 720 380"><rect x="24" y="48" width="166" height="64"></rect>
        <text x="38" y="74">program</text></svg></figure>
      """)
    let url = try #require(URL(string: "data:text/html;base64,\(Data(html.utf8).base64EncodedString())"))
    guard case .page(let page) = try await PageReader.source(at: url, timeout: .seconds(20)) else {
      throw FetchError(reason: "Expected HTML, got PDF")
    }

    #expect(!page.markdown.contains("data:image/svg+xml"))
  }

  @Test(.timeLimit(.minutes(1)))
  func anIconDrawnInThePageIsNotAPicture() async throws {
    let markdown = try await Self.markdown(
      """
      <p>Open it <a href="https://example.com"><svg viewBox="0 0 16 16" width="16" height="16"><path d="M0 0h16v16z"/></svg> here</a>.</p>
      """)

    #expect(!markdown.contains("data:image/svg+xml"))
  }

  @Test(.timeLimit(.minutes(1)))
  func aPictureStillLoadingWhenThePageIsReadIsKept() async throws {
    let markdown = try await Self.markdown(
      """
      <figure><div class="group relative overflow-hidden rounded-none bg-surface-loading">
        <picture><img alt="The relay process" loading="lazy" width="600" height="560"
          src="https://images.example.com/relay-diagram.svg?w=3840"></picture>
      </div></figure>
      """)

    #expect(markdown.contains("https://images.example.com/relay-diagram.svg?w=3840"))
  }

  @Test(.timeLimit(.minutes(1)))
  func textMeantOnlyForScreenReadersIsLeftOut() async throws {
    let markdown = try await Self.markdown(
      """
      <p>We take a <a href="https://en.wikipedia.org/wiki/Defense_in_depth">defense in depth<span class="sr-only">(opens in a new window)</span></a> approach.</p>
      """)

    #expect(markdown.contains("defense in depth"))
    #expect(!markdown.contains("opens in a new window"))
  }

  @Test(.timeLimit(.minutes(1)))
  func aCodeCardKeepsItsFileNameAndLanguageApartAndLosesItsLineNumbers() async throws {
    let markdown = try await Self.markdown(
      """
      <figure class="code"><figcaption><span>enrich-alert/Dockerfile</span><span class="code-lang">dockerfile</span></figcaption>
      <div class="code-body"><pre class="code-lines" aria-hidden="true">1
      2
      3</pre><pre><code><span class="tok-keyword">FROM</span> python:3.13-slim
      <span class="tok-keyword">WORKDIR</span> /app
      <span class="tok-keyword">CMD</span> ["python", "./script.py"]</code></pre></div></figure>
      """)

    #expect(markdown.contains("```dockerfile\nFROM python:3.13-slim"))
    #expect(markdown.contains("enrich-alert/Dockerfile"))
    #expect(!markdown.contains("Dockerfiledockerfile"))
    #expect(!markdown.contains("```\n1\n2\n3"))
  }

  @Test(.timeLimit(.minutes(1)))
  func aCodeCardTitledWithItsLanguageHasNoHeadingForIt() async throws {
    let markdown = try await Self.markdown(
      """
      <div class="flex flex-col overflow-hidden rounded-md"><div class="relative flex justify-between p-5">
        <h4 class="text-p2 font-bold">Python</h4><button type="button">Copy</button></div>
      <div class="code"><pre><code>def spawn_command_under_sandbox(program_and_args, cwd):
          return Child()</code></pre></div></div>
      """)

    #expect(markdown.contains("```python\ndef spawn_command_under_sandbox"))
    #expect(!markdown.contains("#### Python"))
    #expect(!markdown.contains("Copy"))
  }
}
