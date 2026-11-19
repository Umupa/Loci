import Foundation
import LociModel
import WebKit

/// Loads a page in a web view that is never shown and asks defuddle for its text. The web view keeps its
/// cookies in the default store, the one the built-in browser uses, so a site signed into there is signed
/// into here.
@MainActor
final class PageReader: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  /// What to load: an address, or markup that is already here.
  enum Source {
    case url(URL)
    case html(String, base: URL)
  }

  private let webView: WKWebView
  private var loading: CheckedContinuation<Result<Void, FetchError>, Never>?
  private var status: Int?

  private static let world = WKContentWorld.world(name: "loci-reader")
  private static let ready = "lociReady"

  /// defuddle is added to every page as soon as its document is parsed, in a world of its own that the
  /// page's scripts cannot see, and says when it is there.
  private init(store: WKWebsiteDataStore) throws(FetchError) {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = store
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    let scripts = configuration.userContentController
    scripts.addUserScript(
      WKUserScript(
        source: try Self.defuddle() + "\nwebkit.messageHandlers.\(Self.ready).postMessage(null);",
        injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world))
    webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration)
    super.init()
    scripts.add(self, contentWorld: Self.world, name: Self.ready)
    webView.navigationDelegate = self
  }

  /// Gives up after `timeout`, counting from the start of loading to the end of extraction.
  static func read(
    _ source: Source, timeout: Duration, store: WKWebsiteDataStore = .default()
  ) async throws(FetchError) -> Extraction {
    let reader = try PageReader(store: store)
    let deadline = ContinuousClock.now + timeout
    defer {
      reader.webView.stopLoading()
      reader.webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }
    let timer = Task { @MainActor [weak reader] in
      try await Task.sleep(for: timeout)
      reader?.finishLoading(.failure(FetchError(reason: "The page took too long to load.")))
    }
    defer { timer.cancel() }
    try await reader.load(source).get()
    if case .url = source { await reader.waitForTextToSettle() }
    guard ContinuousClock.now < deadline else {
      throw FetchError(reason: "The page took too long to load.")
    }
    return try await reader.extract(at: source)
  }

  private func load(_ source: Source) async -> Result<Void, FetchError> {
    await withCheckedContinuation { continuation in
      loading = continuation
      switch source {
      case .url(let url): webView.load(URLRequest(url: url))
      case .html: webView.loadHTMLString("<!doctype html>", baseURL: nil)
      }
    }
  }

  private func finishLoading(_ result: Result<Void, FetchError>) {
    loading?.resume(returning: result)
    loading = nil
  }

  /// The document is parsed and defuddle is in it. Images and other pieces may still be loading; the
  /// text does not wait for them.
  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    finishLoading(Self.failure(status: status ?? 200).map { .failure($0) } ?? .success(()))
  }

  /// Pages that build their text with JavaScript are still writing it when their document is parsed. Waits
  /// until the amount of text stops growing, for two seconds at most.
  private func waitForTextToSettle() async {
    var last = -1
    for _ in 0..<8 {
      let length = (try? await webView.evaluateJavaScript("document.body ? document.body.innerText.length : 0")) as? Int
      if let length, length == last, length > 0 { return }
      last = length ?? -1
      try? await Task.sleep(for: .milliseconds(250))
    }
  }

  private func extract(at source: Source) async throws(FetchError) -> Extraction {
    let arguments: [String: Any] =
      switch source {
      case .url: ["html": NSNull(), "base": NSNull()]
      case .html(let html, let base): ["html": html, "base": base.absoluteString]
      }
    let reply: Any?
    do {
      reply = try await webView.callAsyncJavaScript(Self.extraction, arguments: arguments, contentWorld: Self.world)
    } catch {
      throw FetchError(reason: "The page's text could not be read: \(error.localizedDescription)")
    }
    guard let json = reply as? String,
      let extraction = try? JSONDecoder().decode(Extraction.self, from: Data(json.utf8))
    else { throw FetchError(reason: "The page's text could not be read.") }
    if case .url(let requested) = source, let landed = webView.url, Self.isSignInPage(landed, requested: requested) {
      throw FetchError(reason: "The site asks you to sign in.", needsLogin: true)
    }
    return extraction
  }

  /// defuddle takes the page's cover image out of the text, expecting it to be shown above the article. Loci
  /// shows no cover there, so the cover is not named and a figure that is also the cover stays where it is.
  private static let extraction = """
    const page = html === null ? document : new DOMParser().parseFromString(html, 'text/html');
    for (const meta of page.querySelectorAll(
      'meta[property="og:image"], meta[name="twitter:image"], meta[name="sailthru.image.full"]')) meta.remove();
    const result = new Defuddle(page, { url: base ?? location.href, separateMarkdown: true }).parse();
    return JSON.stringify({
      title: result.title, author: result.author, site: result.site, published: result.published,
      language: result.language || page.documentElement.lang || "", domain: result.domain,
      markdown: result.contentMarkdown || ""
    });
    """

  /// defuddle's browser build, bundled with the app; see `Resources/defuddle.LICENSE`.
  private static func defuddle() throws(FetchError) -> String {
    guard let url = Bundle.module.url(forResource: "defuddle", withExtension: "js", subdirectory: "Resources"),
      let script = try? String(contentsOf: url, encoding: .utf8)
    else { throw FetchError(reason: "The text extractor is missing from the app.") }
    return script
  }

  /// A page that sent the reader somewhere to sign in, rather than to what was asked for.
  nonisolated static func isSignInPage(_ landed: URL, requested: URL) -> Bool {
    let words = ["login", "log-in", "signin", "sign-in", "sign_in", "auth", "sso", "account/access"]
    let path = landed.path().lowercased()
    let asked = requested.path().lowercased()
    return words.contains { path.contains($0) && !asked.contains($0) }
  }

  /// A page the server refused or could not find. A refusal usually means signing in would help.
  nonisolated static func failure(status: Int) -> FetchError? {
    switch status {
    case 200..<400: nil
    case 401, 403: FetchError(reason: "The site refused the page (HTTP \(status)).", needsLogin: true)
    case 404, 410: FetchError(reason: "The page does not exist (HTTP \(status)).")
    default: FetchError(reason: "The site answered with an error (HTTP \(status)).")
    }
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
  ) async -> WKNavigationResponsePolicy {
    if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse {
      status = response.statusCode
    }
    return .allow
  }

  /// A page whose document never said it was parsed, such as one that is not HTML, has loaded by now.
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    finishLoading(Self.failure(status: status ?? 200).map { .failure($0) } ?? .success(()))
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
    finishLoading(.failure(Self.loadFailure(error)))
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
  ) {
    finishLoading(.failure(Self.loadFailure(error)))
  }

  private static func loadFailure(_ error: any Error) -> FetchError {
    FetchError(reason: "The page could not be loaded: \(error.localizedDescription)")
  }
}
