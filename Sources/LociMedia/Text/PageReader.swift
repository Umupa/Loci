import Foundation
import LociModel
import WebKit

/// Loads a page in a web view that is never shown and asks defuddle for its text, as no one or signed in as the
/// person is in the built-in browser. A signed-in read always sends only GET (`ReadOnlyPage`): the store that
/// holds the sign-ins is reached only through `Visitor.signedIn`, which brings the guards with it.
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
  private var pdf: URL?
  private let purpose: Purpose
  let visitor: Visitor

  private enum Purpose {
    case article
    case source
  }

  /// Who the page is read as.
  enum Visitor {
    /// No one: a store of its own that keeps nothing.
    case anonymous
    /// The person, with the built-in browser's sign-ins; the page may send only GET.
    case signedIn

    fileprivate var store: WKWebsiteDataStore {
      switch self {
      case .anonymous: .nonPersistent()
      case .signedIn: WKWebsiteDataStore.default()
      }
    }
  }

  enum Document {
    case page(Extraction)
    case pdf(URL)
  }

  private static let world = WKContentWorld.world(name: "loci-reader")
  private static let ready = "lociReady"

  /// defuddle is added to every page as soon as its document is parsed, in a world of its own that the
  /// page's scripts cannot see, and says when it is there.
  private init(source: Source, visitor: Visitor, purpose: Purpose) throws(FetchError) {
    self.source = source
    self.purpose = purpose
    self.visitor = visitor
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = visitor.store
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    let scripts = configuration.userContentController
    if visitor == .signedIn {
      scripts.addUserScript(
        WKUserScript(source: ReadOnlyPage.script, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
    }
    scripts.addUserScript(
      WKUserScript(
        source: try Self.defuddle() + "\nwebkit.messageHandlers.\(Self.ready).postMessage(null);",
        injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world))
    webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration)
    super.init()
    scripts.add(self, contentWorld: Self.world, name: Self.ready)
    webView.navigationDelegate = self
  }

  let source: Source
  var address: URL {
    switch source {
    case .url(let requested): webView.url ?? requested
    case .html(_, let base): base
    }
  }

  /// An article: signed in unless told otherwise, so a page the person can read there can be saved.
  static func read(
    _ source: Source, timeout: Duration, as visitor: Visitor = .signedIn
  ) async throws(FetchError) -> Extraction {
    try await open(source, timeout: timeout, as: visitor).extract()
  }

  static func open(
    _ source: Source, timeout: Duration, as visitor: Visitor = .signedIn
  ) async throws(FetchError) -> PageReader {
    try await open(source, timeout: timeout, visitor: visitor, purpose: .article)
  }

  /// A source for the companion to read, as no one unless `signedIn`.
  static func source(at url: URL, timeout: Duration, signedIn: Bool = false) async throws(FetchError) -> Document {
    let reader = try await open(
      .url(url), timeout: timeout, visitor: signedIn ? .signedIn : .anonymous, purpose: .source)
    if let pdf = reader.pdf {
      reader.close()
      return .pdf(pdf)
    }
    return .page(try await reader.extract())
  }

  private static func open(
    _ source: Source, timeout: Duration, visitor: Visitor, purpose: Purpose
  ) async throws(FetchError) -> PageReader {
    let reader = try PageReader(source: source, visitor: visitor, purpose: purpose)
    defer { reader.webView.configuration.userContentController.removeAllScriptMessageHandlers() }
    let timer = Task { @MainActor [weak reader] in
      try await Task.sleep(for: timeout)
      reader?.finishLoading(.failure(FetchError(reason: "The page took too long to load.", cause: .network)))
    }
    defer { timer.cancel() }
    let loaded = await withTaskCancellationHandler {
      await reader.load()
    } onCancel: {
      Task { @MainActor in
        reader.finishLoading(.failure(FetchError(reason: "Page loading was cancelled.")))
        reader.webView.stopLoading()
      }
    }
    do {
      try loaded.get()
    } catch {
      reader.webView.stopLoading()
      throw error
    }
    try reader.checkSignIn()
    return reader
  }

  func head() async -> String {
    switch source {
    case .url: (try? await webView.evaluateJavaScript("document.head?.outerHTML ?? ''")) as? String ?? ""
    case .html(let html, _): html
    }
  }

  private func load() async -> Result<Void, FetchError> {
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
      guard !Task.isCancelled else { return }
      let length = (try? await webView.evaluateJavaScript("document.body ? document.body.innerText.length : 0")) as? Int
      if let length, length == last, length > 0 { return }
      last = length ?? -1
      try? await Task.sleep(for: .milliseconds(250))
    }
  }

  /// The page's text; the page is closed once it is read, so nothing on it runs any more.
  func extract() async throws(FetchError) -> Extraction {
    defer { close() }
    if case .url = source { await waitForTextToSettle() }
    try checkSignIn()
    var arguments: [String: Any] =
      switch source {
      case .url: ["html": NSNull(), "base": NSNull()]
      case .html(let html, let base): ["html": html, "base": base.absoluteString]
      }
    arguments["preferCompleteText"] = purpose != .article
    arguments["keepsDrawings"] = purpose == .article
    let reply: Any?
    do {
      reply = try await webView.callAsyncJavaScript(
        PageTidying.script + Self.extraction, arguments: arguments, contentWorld: Self.world)
    } catch {
      throw FetchError(reason: "The page's text could not be read: \(error.localizedDescription)")
    }
    guard let json = reply as? String,
      let extraction = try? JSONDecoder().decode(Extraction.self, from: Data(json.utf8))
    else { throw FetchError(reason: "The page's text could not be read.") }
    return extraction
  }

  /// Stops the page and leaves it blank: its scripts stop with it.
  func close() {
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.loadHTMLString("", baseURL: nil)
  }

  private func checkSignIn() throws(FetchError) {
    if case .url(let requested) = source, Self.isSignInPage(address, requested: requested) {
      throw FetchError(reason: "The site asks you to sign in.", needsLogin: true)
    }
  }

  /// defuddle takes the page's cover image out of the text, expecting it to be shown above the article. Loci
  /// shows no cover there, so the cover is not named and a figure that is also the cover stays where it is.
  private static let extraction = #"""
    const page = html === null ? document : new DOMParser().parseFromString(html, 'text/html');
    for (const meta of page.querySelectorAll(
      'meta[property="og:image"], meta[name="twitter:image"], meta[name="sailthru.image.full"]')) meta.remove();
    lociTidy(page, html === null, keepsDrawings);
    const url = base ?? location.href;
    const result = new Defuddle(page, { url, separateMarkdown: true }).parse();
    let markdown = result.contentMarkdown || "";
    if (preferCompleteText) {
      const root = page.querySelector('main, [role="main"]') ?? page.body;
      const visible = root?.innerText ?? "";
      const extracted = new DOMParser().parseFromString(result.content || "", "text/html").body.textContent;
      const length = text => text.replace(/\s/g, "").length;
      if (root && length(extracted) * 3 < length(visible)) {
        const copy = root.cloneNode(true);
        const copies = copy.querySelectorAll("*");
        for (const [index, element] of root.querySelectorAll("*").entries()) {
          const kept = copies[index];
          if (!copy.contains(kept)) continue;
          const style = getComputedStyle(element);
          if (element.matches("nav, aside, footer, script, style, noscript, template, " +
                              '[role="navigation"], [role="complementary"], [role="contentinfo"]') ||
              style.display === "none" || style.visibility === "hidden" || style.visibility === "collapse" ||
              style.contentVisibility === "hidden") {
            kept.remove();
            continue;
          }
          if (element instanceof HTMLAnchorElement && element.hasAttribute("href") &&
              !element.getAttribute("href").startsWith("#")) kept.setAttribute("href", element.href);
          if (element instanceof HTMLImageElement && element.hasAttribute("src")) kept.setAttribute("src", element.src);
        }
        markdown = Defuddle.createMarkdownContent(copy.innerHTML, url) || markdown;
      }
    }
    return JSON.stringify({
      title: result.title, author: result.author, site: result.site, published: result.published,
      language: result.language || page.documentElement.lang || "", domain: result.domain,
      markdown
    });
    """#

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
    case 404, 410: FetchError(reason: "The page does not exist (HTTP \(status)).", cause: .unavailable)
    default: FetchError(reason: "The site answered with an error (HTTP \(status)).")
    }
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
  ) async -> WKNavigationActionPolicy {
    guard visitor == .signedIn else { return .allow }
    return ReadOnlyPage.allows(method: navigationAction.request.httpMethod) ? .allow : .cancel
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
  ) async -> WKNavigationResponsePolicy {
    if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse {
      status = response.statusCode
      if purpose != .article, response.mimeType == "application/pdf", let url = response.url,
        Self.failure(status: response.statusCode) == nil
      {
        pdf = url
        finishLoading(.success(()))
        return .cancel
      }
    }
    return .allow
  }

  func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge)
    async -> (URLSession.AuthChallengeDisposition, URLCredential?)
  {
    if purpose != .article, challenge.protectionSpace.authenticationMethod != NSURLAuthenticationMethodServerTrust {
      return (.cancelAuthenticationChallenge, nil)
    }
    return (.performDefaultHandling, nil)
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
    FetchError(reason: "The page could not be loaded: \(error.localizedDescription)", cause: .network)
  }
}
