import Foundation
import LociModel
import WebKit

/// Where a source's script runs: a page made for one call. Each thing it is asked may never be answered, by a
/// page whose process is stuck; `ParseSandbox` holds each to a deadline, and `close` drops the page whatever
/// it is doing, answering what is still waiting.
@MainActor
protocol SandboxPage: AnyObject, Sendable {
  /// Loads the blank page the script runs in; whether it did.
  func load() async -> Bool
  /// Runs `body` on the page with `inputText`; what it returned, or why it did not.
  func evaluate(_ body: String, input: String) async -> Result<String, SourceProblems>
  /// Asks the page once to end its worker; whether the page says it has, or its process is gone.
  func endWorker() async -> Bool
  func close()
}

/// The page as a web view no one sees. Nothing but this holds the web view, not even a call still waiting on
/// the page, so closing drops it, and WebKit ends its process with it.
///
/// The page's content security policy allows no connection, image, frame or other load, and workers only
/// from the page's own blob (`default-src 'none'; worker-src blob:`); the navigation delegate lets nothing
/// but the blank page load; the data store keeps nothing; and each call gets a fresh page, so one source
/// never sees another or its own last run.
@MainActor
final class WebSandboxPage: NSObject, SandboxPage, WKNavigationDelegate {
  static let page = """
    <!doctype html><html><head><meta http-equiv="Content-Security-Policy" \
    content="default-src 'none'; connect-src 'none'; form-action 'none'; worker-src blob:"></head><body></body></html>
    """

  private var webView: WKWebView?
  private var loading: CheckedContinuation<Bool, Never>?
  private var answer: CheckedContinuation<Result<String, SourceProblems>, Never>?
  private var processEnded = false

  override init() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: configuration)
    super.init()
    webView?.navigationDelegate = self
  }

  func load() async -> Bool {
    await withCheckedContinuation { continuation in
      loading = continuation
      if webView?.loadHTMLString(Self.page, baseURL: nil) == nil { finishLoading(false) }
    }
  }

  func evaluate(_ body: String, input: String) async -> Result<String, SourceProblems> {
    await withCheckedContinuation { continuation in
      answer = continuation
      guard let webView else { return respond(.failure(Self.closed)) }
      webView.callAsyncJavaScript(body, arguments: ["inputText": input], in: nil, in: .page) { [weak self] result in
        switch result {
        case .success(let value):
          self?.respond((value as? String).map { .success($0) } ?? .failure(Self.nothing))
        case .failure(let error): self?.respond(.failure(Self.problems(error)))
        }
      }
    }
  }

  func endWorker() async -> Bool {
    guard !processEnded, let webView else { return true }
    return await withCheckedContinuation { continuation in
      webView.callAsyncJavaScript(
        "if (window.lociWorker) { window.lociWorker.terminate(); window.lociWorker = null; } return true;",
        arguments: [:], in: nil, in: .page
      ) { [weak self] result in
        continuation.resume(returning: self?.processEnded == true || (try? result.get()) as? Bool == true)
      }
    }
  }

  func close() {
    webView?.stopLoading()
    webView?.navigationDelegate = nil
    webView = nil
    finishLoading(false)
    respond(.failure(Self.closed))
  }

  private static let closed = SourceProblems("script", "its page was closed")
  private static let nothing = SourceProblems("script", "returned nothing")

  private static func problems(_ error: any Error) -> SourceProblems {
    let info = (error as NSError).userInfo
    let message = info["WKJavaScriptExceptionMessage"] as? String ?? (error as NSError).localizedDescription
    let line = (info["WKJavaScriptExceptionLineNumber"] as? Int).map { " (line \($0))" } ?? ""
    return SourceProblems("script", "\(message)\(line)")
  }

  private func respond(_ result: Result<String, SourceProblems>) {
    let waiting = answer
    answer = nil
    waiting?.resume(returning: result)
  }

  private func finishLoading(_ loaded: Bool) {
    let waiting = loading
    loading = nil
    waiting?.resume(returning: loaded)
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
    loading != nil && action.request.url?.absoluteString == "about:blank" ? .allow : .cancel
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading(true) }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
    finishLoading(false)
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error)
  {
    finishLoading(false)
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    processEnded = true
    finishLoading(false)
    respond(.failure(SourceProblems("script", "its page stopped")))
  }
}
