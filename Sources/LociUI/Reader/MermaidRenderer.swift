import AppKit
import WebKit

@MainActor
final class MermaidRenderer: NSObject, WKNavigationDelegate {
  typealias Render = @MainActor ([String], Bool) async -> [String: NSImage]

  private let page: URL
  private let webView: WKWebView
  private var loading: CheckedContinuation<Bool, Never>?

  private init(page: URL) {
    self.page = page
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
    super.init()
    webView.navigationDelegate = self
  }

  static func render(_ sources: [String], dark: Bool) async -> [String: NSImage] {
    guard !sources.isEmpty,
      let page = Bundle.module.url(forResource: "renderer", withExtension: "html", subdirectory: "Mermaid")
    else { return [:] }
    let renderer = MermaidRenderer(page: page)
    guard await renderer.load() else { return [:] }
    var images: [String: NSImage] = [:]
    for source in sources {
      guard !Task.isCancelled else { break }
      images[source] = try? await renderer.image(source: source, dark: dark)
    }
    return images
  }

  private func load() async -> Bool {
    await withTaskCancellationHandler {
      guard !Task.isCancelled else { return false }
      return await withCheckedContinuation { continuation in
        loading = continuation
        if webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent()) == nil { finish(false) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.finish(false)
        self?.webView.stopLoading()
      }
    }
  }

  private func finish(_ result: Bool) {
    let waiting = loading
    loading = nil
    waiting?.resume(returning: result)
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
    action.targetFrame?.isMainFrame == true && action.request.url == page ? .allow : .cancel
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(false) }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error)
  {
    finish(false)
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(false) }

  private func image(source: String, dark: Bool) async throws -> NSImage? {
    let size =
      try await webView.callAsyncJavaScript(
        Self.draw, arguments: ["source": source, "dark": dark], contentWorld: .page) as? [Double]
    guard let size, size.count == 2, size.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 12_000 }) else { return nil }
    let configuration = WKPDFConfiguration()
    configuration.rect = CGRect(x: 0, y: 0, width: size[0].rounded(.up), height: size[1].rounded(.up))
    configuration.allowTransparentBackground = true
    let data = try await webView.pdf(configuration: configuration)
    return NSImage(data: data)
  }

  private static let draw = #"""
    const output = document.querySelector('main');
    output.replaceChildren();
    mermaid.initialize({
      startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
      theme: dark ? 'dark' : 'neutral', fontFamily: 'system-ui, sans-serif',
    });
    const { svg } = await mermaid.render('loci-diagram', source);
    output.innerHTML = svg;
    const diagram = output.querySelector('svg');
    const { width, height } = diagram.viewBox.baseVal;
    diagram.style.maxWidth = 'none';
    diagram.setAttribute('width', width);
    diagram.setAttribute('height', height);
    return [width, height];
    """#
}

final class MermaidAttachment: NSTextAttachment {
  let source: String

  init(image: NSImage, source: String) {
    self.source = source
    super.init(data: nil, ofType: nil)
    self.image = image
  }

  required init?(coder: NSCoder) { nil }

  override func attachmentBounds(
    for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
    proposedLineFragment: CGRect, position: CGPoint
  ) -> CGRect {
    guard let size = image?.size, size.width > 0 else { return .zero }
    let width = min(size.width, max(1, proposedLineFragment.width))
    return CGRect(x: 0, y: 0, width: width, height: size.height * width / size.width)
  }
}
