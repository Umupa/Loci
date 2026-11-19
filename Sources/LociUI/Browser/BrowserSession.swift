import Foundation
import LociModel
import WebKit

/// The built-in browser: one web view for the window, kept while the reader goes elsewhere and comes back.
///
/// It shares the system's website data with the hidden pages that fetch articles, so a site signed in to here
/// is signed in to there. After each load a script reports what the page holds, which decides the button
/// beside the address.
@MainActor
@Observable
final class BrowserSession {
  private(set) var address: URL?
  private(set) var canGoBack = false
  private(set) var canGoForward = false
  private(set) var loading = false
  private(set) var facts = PageFacts()
  @ObservationIgnored private var view: WKWebView?
  @ObservationIgnored private var watcher: PageWatcher?

  /// The web view, made the first time the browser is shown.
  var webView: WKWebView {
    if let view { return view }
    let watcher = PageWatcher(session: self)
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    configuration.userContentController.addUserScript(
      WKUserScript(source: PageScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    configuration.userContentController.add(watcher, name: PageScript.channel)
    let made = WKWebView(frame: .zero, configuration: configuration)
    made.navigationDelegate = watcher
    made.allowsBackForwardNavigationGestures = true
    view = made
    self.watcher = watcher
    if let address { made.load(URLRequest(url: address)) }
    return made
  }

  /// Opens a page; `nil` leaves the browser where it is.
  func open(_ url: URL?) {
    guard let url else { return }
    address = url
    facts = PageFacts()
    view?.load(URLRequest(url: url))
  }

  /// Goes to what was typed: an address as it is, a bare domain over https, anything else as a search.
  func go(to typed: String) {
    open(Self.destination(of: typed))
  }

  func back() { view?.goBack() }
  func forward() { view?.goForward() }
  func reload() { view?.reload() }

  /// Leaves the browser for its start page.
  func home() {
    view?.stopLoading()
    address = nil
    facts = PageFacts()
  }

  /// The cookies the browser holds for `url`'s site, to fetch it signed in.
  func cookies(for url: URL) async -> [BrowserCookie] {
    guard let host = url.host()?.lowercased() else { return [] }
    let store = WKWebsiteDataStore.default().httpCookieStore
    let all = await store.allCookies()
    return all.filter { cookie in
      let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
      return host == domain || host.hasSuffix("." + domain) || domain.hasSuffix("." + Self.site(of: host))
    }
    .map { cookie in
      BrowserCookie(
        domain: cookie.domain, path: cookie.path, name: cookie.name, value: cookie.value, secure: cookie.isSecure,
        expires: cookie.expiresDate.map(Timestamp.init))
    }
  }

  fileprivate func update(from view: WKWebView) {
    if let url = view.url, url.isWebLink {
      if PageAddress(url) != address.map(PageAddress.init) { facts = PageFacts() }
      address = url
    }
    canGoBack = view.canGoBack
    canGoForward = view.canGoForward
    loading = view.isLoading
  }

  func learn(_ reported: PageFacts) {
    facts.videos = reported.videos
    facts.hasArticle = reported.hasArticle
  }

  fileprivate func showingPDF() {
    facts.isPDF = true
  }

  static func destination(of typed: String) -> URL? {
    let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if let url = URL(webLinkText: text) { return url }
    if !text.contains(" "), text.contains("."), let url = URL(string: "https://" + text), url.host() != nil {
      return url
    }
    var search = URLComponents(string: "https://www.google.com/search")
    search?.queryItems = [URLQueryItem(name: "q", value: text)]
    return search?.url
  }

  /// The last two labels of a host name, such as `youtube.com`.
  private static func site(of host: String) -> String {
    host.split(separator: ".").suffix(2).joined(separator: ".")
  }
}

/// Hears the web view's loads and the page script's reports, and passes them to the session.
@MainActor
private final class PageWatcher: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  weak var session: BrowserSession?

  init(session: BrowserSession) {
    self.session = session
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    session?.update(from: webView)
  }

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    session?.update(from: webView)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    session?.update(from: webView)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
    session?.update(from: webView)
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
  ) async -> WKNavigationResponsePolicy {
    if navigationResponse.isForMainFrame, navigationResponse.response.mimeType == "application/pdf" {
      session?.showingPDF()
    }
    return .allow
  }

  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let session, let view = message.webView else { return }
    session.update(from: view)
    if let report = PageScript.facts(from: message.body) { session.learn(report) }
  }
}
