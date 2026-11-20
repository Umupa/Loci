import Foundation
import LociModel
import WebKit

/// The built-in browser: the tabs of one window, kept while the reader goes elsewhere and comes back.
///
/// Every tab shares the system's website data with the hidden pages that fetch articles, so a site signed in
/// to here is signed in to there. When the reader agreed, each launch starts with the sign-ins of the browser
/// they use. After each load a script reports what the page holds, which decides the button beside the address.
@MainActor
@Observable
final class BrowserSession {
  private(set) var tabs: [BrowserTab]
  private(set) var current: BrowserTab
  /// A browser whose sign-ins the start page offers, until the reader answers.
  private(set) var signInOffer: SignInBrowser?
  /// Goes up each time the address field should take the cursor.
  private(set) var addressFocus = 0
  @ObservationIgnored private let signIns: (any BrowserSignIns)?
  @ObservationIgnored private var signedIn = false
  @ObservationIgnored private var watcher: PageWatcher?
  @ObservationIgnored private var configuration: WKWebViewConfiguration?

  init(signIns: (any BrowserSignIns)? = nil) {
    let first = BrowserTab()
    tabs = [first]
    current = first
    self.signIns = signIns
  }

  /// The tab's web view, made the first time it is shown.
  func webView(for tab: BrowserTab) -> WKWebView {
    if let view = tab.view { return view }
    let made = WKWebView(frame: .zero, configuration: sharedConfiguration())
    prepare(made)
    tab.attach(made)
    return made
  }

  /// Opens a page: in the tab in front when it shows the start page, otherwise in a new tab.
  func open(_ url: URL?) {
    guard let url else { return }
    if !current.atStart || current.address != nil { newTab() }
    current.open(url)
  }

  /// Goes to what was typed: an address as it is, a bare domain over https, anything else as a search.
  func go(to typed: String) {
    current.open(Self.destination(of: typed))
  }

  func newTab() {
    let tab = BrowserTab()
    tabs.insert(tab, at: (tabs.firstIndex { $0 === current } ?? tabs.count - 1) + 1)
    current = tab
    focusAddress()
  }

  /// Closes a tab and shows the one before it, which for a window a page opened is that page. Closing the last
  /// one leaves a start page.
  func close(_ tab: BrowserTab) {
    guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
    tab.view?.stopLoading()
    tabs.remove(at: index)
    if tabs.isEmpty { tabs = [BrowserTab()] }
    if current === tab { current = tabs[max(index - 1, 0)] }
  }

  func select(_ tab: BrowserTab) {
    current = tab
  }

  func focusAddress() {
    addressFocus += 1
  }

  /// The cookies the browser holds for `url`'s site, to fetch it signed in.
  func cookies(for url: URL) async -> [BrowserCookie] {
    guard let host = url.host()?.lowercased() else { return [] }
    let all = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
    return all.filter { cookie in
      let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
      return host == domain || host.hasSuffix("." + domain) || domain.hasSuffix("." + Self.site(of: host))
    }
    .map { cookie in
      BrowserCookie(
        domain: cookie.domain, path: cookie.path, name: cookie.name, value: cookie.value, secure: cookie.isSecure,
        expires: cookie.expiresDate.map(Timestamp.init), httpOnly: cookie.isHTTPOnly)
    }
  }

  /// Brings in the sign-ins of the browser in use, once a launch, or finds which one to offer.
  func checkSignIns() async {
    guard let signIns, !signedIn else { return }
    switch await signIns.choice() {
    case .offer(let browser):
      signInOffer = browser
    case .using:
      signInOffer = nil
      signedIn = true
      if let cookies = try? await signIns.currentCookies() { await take(cookies) }
    case .declined, .unavailable:
      signInOffer = nil
    }
  }

  func acceptSignIns(from browser: SignInBrowser) async {
    guard let signIns else { return }
    signInOffer = nil
    if let cookies = try? await signIns.use(browser) {
      signedIn = true
      await take(cookies)
    }
  }

  func declineSignIns() async {
    signInOffer = nil
    await signIns?.decline()
  }

  /// Puts the cookies into the browser's store and reloads the pages open, so they show signed in.
  private func take(_ cookies: [BrowserCookie]) async {
    let store = WKWebsiteDataStore.default().httpCookieStore
    for cookie in cookies {
      if let made = HTTPCookie(cookie) { await store.setCookie(made) }
    }
    for tab in tabs where tab.view?.url != nil { tab.reload() }
  }

  /// A tab for a window a page opened, beside the page, with the configuration WebKit gives.
  fileprivate func popUp(with configuration: WKWebViewConfiguration) -> WKWebView {
    let made = WKWebView(frame: .zero, configuration: configuration)
    prepare(made)
    newTab()
    current.attach(made)
    return made
  }

  fileprivate func tab(showing view: WKWebView) -> BrowserTab? {
    tabs.first { $0.view === view }
  }

  private func prepare(_ view: WKWebView) {
    view.navigationDelegate = watcher
    view.uiDelegate = watcher
    view.allowsBackForwardNavigationGestures = true
  }

  /// One configuration for every tab, so the page script reports to one watcher.
  private func sharedConfiguration() -> WKWebViewConfiguration {
    if let configuration { return configuration }
    let watcher = PageWatcher(session: self)
    let made = WKWebViewConfiguration()
    made.websiteDataStore = .default()
    let version = ProcessInfo.processInfo.operatingSystemVersion
    made.applicationNameForUserAgent = "Version/\(version.majorVersion).\(version.minorVersion) Safari/605.1.15"
    made.userContentController.addUserScript(
      WKUserScript(source: PageScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    made.userContentController.add(watcher, name: PageScript.channel)
    self.watcher = watcher
    configuration = made
    return made
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

extension HTTPCookie {
  fileprivate convenience init?(_ cookie: BrowserCookie) {
    var properties: [HTTPCookiePropertyKey: Any] = [
      .domain: cookie.domain, .path: cookie.path, .name: cookie.name, .value: cookie.value,
    ]
    if cookie.secure { properties[.secure] = "TRUE" }
    if let expires = cookie.expires { properties[.expires] = expires.date }
    if cookie.httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
    self.init(properties: properties)
  }
}

/// Hears every tab's loads, the windows its pages open and close, and the page script's reports.
@MainActor
private final class PageWatcher: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
  weak var session: BrowserSession?

  init(session: BrowserSession) {
    self.session = session
  }

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    session?.tab(showing: webView)?.update(from: webView)
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
  ) async -> WKNavigationResponsePolicy {
    if navigationResponse.isForMainFrame, navigationResponse.response.mimeType == "application/pdf" {
      session?.tab(showing: webView)?.showingPDF()
    }
    return .allow
  }

  /// A link meant for a new window, or a window a script opens such as a sign-in, becomes a tab.
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    session?.popUp(with: configuration)
  }

  /// A window that closes itself, such as a finished sign-in, closes its tab.
  func webViewDidClose(_ webView: WKWebView) {
    guard let session, let tab = session.tab(showing: webView) else { return }
    session.close(tab)
  }

  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let view = message.webView, let tab = session?.tab(showing: view) else { return }
    tab.update(from: view)
    if let report = PageScript.facts(from: message.body) { tab.learn(report) }
  }
}
