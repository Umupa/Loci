import AppKit
import LociModel
import WebKit

/// Turns the pages of one book in a web view: a chapter at a time, set in columns a page wide, moved a page at a
/// time. Where the reader is is kept as a `BookSpot`, so it survives any change of size or setting.
@MainActor
@Observable
final class BookReader: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  let item: EntityID
  let contents: BookContents
  let webView: WKWebView
  private(set) var chapter = 0
  private(set) var page = 0
  private(set) var pages = 1
  /// Where a link inside the book was followed from, for going back to it.
  private(set) var back: BookSpot?
  /// The place the page shows now; it is what is restored after the layout changes.
  private(set) var spot: BookSpot?
  private(set) var layout: BookLayout
  @ObservationIgnored let files: BookFiles
  @ObservationIgnored var moved: (BookSpot) -> Void = { _ in }
  @ObservationIgnored var finished: () -> Void = {}
  @ObservationIgnored var openLink: (URL) -> Void = { _ in }
  @ObservationIgnored private var loading: CheckedContinuation<Bool, Never>?
  @ObservationIgnored private var loadedAsHTML = false
  @ObservationIgnored private var busy = false

  init(item: EntityID, contents: BookContents, files: BookFiles, layout: BookLayout) {
    self.item = item
    self.contents = contents
    self.files = files
    self.layout = layout
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.setURLSchemeHandler(files, forURLScheme: BookFiles.scheme)
    if let script = Bundle.module.url(forResource: "BookPager", withExtension: "js"),
      let source = try? String(contentsOf: script, encoding: .utf8)
    {
      configuration.userContentController.addUserScript(
        WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }
    webView = WKWebView(
      frame: CGRect(x: 0, y: 0, width: layout.width, height: 600), configuration: configuration)
    webView.underPageBackgroundColor = Tones.canvas
    webView.setValue(false, forKey: "drawsBackground")
    super.init()
    configuration.userContentController.add(WeakHandler(self), name: "book")
    webView.navigationDelegate = self
  }

  /// How far into the whole book the page is.
  var share: Fraction {
    contents.share(chapter: chapter, within: pages > 1 ? Double(page) / Double(pages - 1) : 0)
  }

  var atEnd: Bool { chapter == contents.chapters.count - 1 && page == pages - 1 }

  func open(at spot: BookSpot?) async {
    guard let spot, contents.chapters.indices.contains(spot.chapter) else {
      await show(chapter: 0, page: 0)
      return
    }
    await show(spot)
  }

  func turn(_ step: Int) async {
    guard !busy else { return }
    if step > 0, page + 1 < pages {
      await go(page + 1)
    } else if step > 0, chapter + 1 < contents.chapters.count {
      await show(chapter: chapter + 1, page: 0)
    } else if step < 0, page > 0 {
      await go(page - 1)
    } else if step < 0, chapter > 0 {
      await show(chapter: chapter - 1, page: .max)
    }
    if step > 0, atEnd { finished() }
  }

  /// Opens the table of contents' entry: its chapter, at its anchor when it has one.
  func show(_ entry: BookContents.Entry) async {
    back = nil
    await show(chapter: entry.chapter, anchor: entry.anchor)
  }

  /// Jumps to a share of the whole book, as the progress bar is let go.
  func show(share: Fraction) async {
    guard let place = contents.place(of: share) else { return }
    back = nil
    await show(chapter: place.chapter) { pages in Int((place.within.value * Double(pages - 1)).rounded()) }
  }

  func goBack() async {
    guard let back else { return }
    self.back = nil
    await show(back)
  }

  func relayout(_ layout: BookLayout) async {
    guard layout != self.layout else { return }
    self.layout = layout
    guard !busy, loading == nil else { return }
    busy = true
    defer { busy = false }
    pages = await arrange()
    let target = await page(of: spot) ?? min(page, pages - 1)
    await go(target, remember: false)
  }

  func follow(_ url: URL) async {
    guard let place = BookFiles.place(of: url) else {
      if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" { openLink(url) }
      return
    }
    guard let target = contents.chapters.firstIndex(where: { $0.path == place.path }) else { return }
    back = spot
    await show(chapter: target, anchor: place.anchor)
  }

  private func show(_ spot: BookSpot) async {
    await show(chapter: spot.chapter) { [weak self] _ in await self?.page(of: spot) ?? 0 }
  }

  private func show(chapter: Int, anchor: String?) async {
    await show(chapter: chapter) { [weak self] _ in
      guard let anchor else { return 0 }
      return await self?.number("loci.pageOfAnchor(\(Self.json(anchor)))") ?? 0
    }
  }

  private func show(chapter target: Int, page wanted: Int) async {
    await show(chapter: target) { pages in min(wanted, pages - 1) }
  }

  private func show(chapter target: Int, at pick: @MainActor (Int) async -> Int) async {
    guard contents.chapters.indices.contains(target), !busy else { return }
    busy = true
    defer { busy = false }
    if target != chapter || webView.url == nil {
      guard await load(target) else { return }
      chapter = target
    }
    pages = await arrange()
    await go(max(0, min(await pick(pages), pages - 1)))
    if contents.chapters.indices.contains(target + 1) { files.prefetch(contents.chapters[target + 1].path) }
  }

  private func load(_ target: Int) async -> Bool {
    let path = contents.chapters[target].path
    guard let url = BookFiles.url(of: path), await navigate(to: url) else { return false }
    if await (try? webView.evaluateJavaScript("loci.broken()")) as? Bool == true,
      let html = BookFiles.url(of: path, asHTML: true)
    {
      return await navigate(to: html)
    }
    return true
  }

  private func navigate(to url: URL) async -> Bool {
    loading?.resume(returning: false)
    return await withCheckedContinuation { continuation in
      loading = continuation
      webView.load(URLRequest(url: url))
    }
  }

  private func arrange() async -> Int {
    let call = "loci.layout(\(Self.json(layout.css)), \(layout.margin), \(Self.json(contents.language ?? "")))"
    _ = try? await webView.evaluateJavaScript(call)
    let pages = (try? await webView.callAsyncJavaScript("return await loci.ready()", contentWorld: .page)) as? Int
    return max(1, pages ?? 1)
  }

  private func go(_ target: Int, remember: Bool = true) async {
    page = target
    _ = try? await webView.evaluateJavaScript("loci.go(\(target))")
    if remember { await note() }
  }

  private func note() async {
    let found = (try? await webView.evaluateJavaScript("loci.spot()")) as? [String: Any]
    let node = (found?["node"] as? [Int]).flatMap { $0.isEmpty ? nil : $0 } ?? [0]
    let character = found?["character"] as? Int ?? 0
    guard let spot = try? BookSpot(chapter: chapter, node: node, character: character, share: share) else { return }
    self.spot = spot
    moved(spot)
  }

  private func page(of spot: BookSpot?) async -> Int? {
    guard let spot, spot.chapter == chapter else { return nil }
    return await number("loci.pageOf(\(Self.json(spot.node)), \(spot.character))")
  }

  private func number(_ script: String) async -> Int? {
    (try? await webView.evaluateJavaScript(script)) as? Int
  }

  static func json(_ value: some Encodable) -> String {
    (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(false) }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
  ) {
    finish(false)
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
    guard let url = action.request.url else { return .cancel }
    if action.navigationType == .linkActivated {
      await follow(url)
      return .cancel
    }
    return url.scheme == BookFiles.scheme ? .allow : .cancel
  }

  private func finish(_ result: Bool) {
    let waiting = loading
    loading = nil
    waiting?.resume(returning: result)
  }

  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    let body = message.body as? [String: Any]
    let turn = body?["turn"] as? Int
    let link = (body?["link"] as? String).flatMap(URL.init(string:))
    Task {
      if let turn { await self.turn(turn) }
      if let link { await self.follow(link) }
    }
  }
}

/// Holds the reader weakly, so the web view's script handler does not keep it alive.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
  weak var target: (any WKScriptMessageHandler)?

  init(_ target: any WKScriptMessageHandler) {
    self.target = target
  }

  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(controller, didReceive: message)
  }
}
