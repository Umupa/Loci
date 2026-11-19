import Foundation
import LociModel
import WebKit

/// One tab of the built-in browser: its page, or the start page in front of it.
@MainActor
@Observable
final class BrowserTab: Identifiable {
  private(set) var address: URL?
  private(set) var title = ""
  /// How far the page has loaded; `nil` once it has.
  private(set) var progress: Double?
  private(set) var facts = PageFacts()
  /// The start page is in front. A page may be behind it, which going back shows again.
  private(set) var atStart = true
  private var webCanGoBack = false
  private(set) var canGoForward = false
  /// Made the first time the tab shows a page, or given by a page that opened a window.
  @ObservationIgnored private(set) var view: WKWebView?
  @ObservationIgnored private var watching: [NSKeyValueObservation] = []

  init() {}

  var canGoBack: Bool { atStart ? address != nil : webCanGoBack }

  /// What the tab is called in the tab strip: the page's title, else its site.
  var name: String? {
    if atStart { return nil }
    if !title.isEmpty { return title }
    return address?.host()
  }

  /// Shows `view` in this tab and follows its address, title and loading.
  func attach(_ view: WKWebView) {
    self.view = view
    watching = [
      view.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { self?.update(from: view) } },
      view.observe(\.title) { [weak self] view, _ in MainActor.assumeIsolated { self?.update(from: view) } },
      view.observe(\.estimatedProgress) { [weak self] view, _ in
        MainActor.assumeIsolated { self?.update(from: view) }
      },
      view.observe(\.isLoading) { [weak self] view, _ in MainActor.assumeIsolated { self?.update(from: view) } },
      view.observe(\.canGoBack) { [weak self] view, _ in MainActor.assumeIsolated { self?.update(from: view) } },
      view.observe(\.canGoForward) { [weak self] view, _ in
        MainActor.assumeIsolated { self?.update(from: view) }
      },
    ]
    atStart = false
    if let address, view.url == nil { view.load(URLRequest(url: address)) }
  }

  /// Opens a page in this tab; `nil` leaves it where it is.
  func open(_ url: URL?) {
    guard let url else { return }
    address = url
    facts = PageFacts()
    atStart = false
    view?.load(URLRequest(url: url))
  }

  func back() {
    if atStart {
      atStart = false
    } else {
      view?.goBack()
    }
  }

  func forward() { view?.goForward() }
  func reload() { view?.reload() }

  /// Puts the start page in front, keeping the page behind it.
  func home() {
    atStart = true
    progress = nil
  }

  func learn(_ reported: PageFacts) {
    facts.videos = reported.videos
    facts.hasArticle = reported.hasArticle
  }

  func showingPDF() {
    facts.isPDF = true
  }

  func articleHTML(at address: URL) async -> String? {
    guard LinkKind(address) == .article, facts.hasArticle, !facts.isPDF, let view, view.url == address,
      let report = try? await view.callAsyncJavaScript(PageScript.article, contentWorld: .defaultClient)
        as? [String: String],
      report["url"].flatMap(URL.init(string:)) == address, let html = report["html"],
      html.utf8.count <= AddLink.maximumArticleBytes
    else { return nil }
    return html
  }

  func update(from view: WKWebView) {
    if let url = view.url, url.isWebLink {
      if PageAddress(url) != address.map(PageAddress.init) { facts = PageFacts() }
      address = url
    }
    title = view.title ?? ""
    webCanGoBack = view.canGoBack
    canGoForward = view.canGoForward
    progress = view.isLoading ? view.estimatedProgress : nil
  }
}
