import Foundation
import LociModel
import WebKit

/// Runs a source's script in a web view no one sees, made for that one call and dropped after it.
///
/// What holds the script in: it runs in a worker the page starts, and the page ends the worker when its time
/// is up, because dropping a web view leaves a script stuck in a loop running in its process. The page's
/// content security policy allows no connection, image, frame or other load, and workers only from the
/// page's own blob (`default-src 'none'; worker-src blob:`); the navigation delegate lets nothing but the
/// blank page load; the app's prelude takes `fetch`, `XMLHttpRequest`, `WebSocket`, `importScripts` and
/// storage away inside the worker; the data store keeps nothing; and each call gets a fresh page, so one
/// source never sees another or its own last run.
@MainActor
final class ParseSandbox: NSObject, WKNavigationDelegate {
  /// What the script is asked for.
  enum Call {
    case requests(state: JSONValue?)
    case parse(responses: [SourceResponse])
  }

  static let page = """
    <!doctype html><html><head><meta http-equiv="Content-Security-Policy" \
    content="default-src 'none'; connect-src 'none'; form-action 'none'; worker-src blob:"></head><body></body></html>
    """

  private var webView: WKWebView?
  private var loading: CheckedContinuation<Bool, Never>?
  private var answer: CheckedContinuation<Result<String, SourceProblems>, Never>?

  private override init() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: configuration)
    super.init()
    webView?.navigationDelegate = self
  }

  /// What the script's `requests(state)` or `parse(responses, now)` returned, as JSON.
  static func run(_ script: String, _ call: Call, now: Timestamp, timeout: Duration) async throws(SourceProblems)
    -> JSONValue
  {
    let sandbox = ParseSandbox()
    defer { sandbox.close() }
    guard await sandbox.load() else { throw SourceProblems("sandbox", "the page to run the script in did not load") }
    let text = try await sandbox.evaluate(
      try page(script, call, timeout: timeout), input: try input(call, now: now), timeout: timeout + .seconds(2))
    return try answer(text, call: call, timeout: timeout)
  }

  /// The page's side: starts the worker, hands it the input, and ends it when it answers or runs out of time.
  private static func page(_ script: String, _ call: Call, timeout: Duration) throws(SourceProblems) -> String {
    guard let url = Bundle.module.url(forResource: "source-sandbox", withExtension: "js", subdirectory: "Resources"),
      let prelude = try? String(contentsOf: url, encoding: .utf8)
    else { throw SourceProblems("sandbox", "the sandbox's script is missing from the app") }
    let invocation =
      switch call {
      case .requests: "requests(input.state)"
      case .parse: "parse(input.responses, now)"
      }
    let worker = """
      onmessage = async (message) => {
        const input = JSON.parse(message.data);
        \(prelude)
        try {
          postMessage(JSON.stringify({ value: await (async () => {
      \(script)
      ;return \(invocation);
          })() }));
        } catch (error) {
          postMessage(JSON.stringify({ error: String((error && error.message) || error) }));
        }
      };
      """
    let milliseconds = timeout.components.seconds * 1000 + timeout.components.attoseconds / 1_000_000_000_000_000
    return """
      const code = URL.createObjectURL(new Blob([\(JSONValue.string(worker).text)], { type: "text/javascript" }));
      const worker = new Worker(code);
      return await new Promise((resolve) => {
        const end = (answer) => { clearTimeout(timer); worker.terminate(); resolve(JSON.stringify(answer)); };
        const timer = setTimeout(() => end({ timeout: true }), \(milliseconds));
        worker.onmessage = (message) => end(JSON.parse(message.data));
        worker.onerror = (event) => { event.preventDefault(); end({ error: event.message, line: event.lineno }); };
        worker.postMessage(inputText);
      });
      """
  }

  private static func answer(_ text: String, call: Call, timeout: Duration) throws(SourceProblems) -> JSONValue {
    guard let envelope = JSONValue(parsing: text) else { throw nothing }
    if envelope["timeout"] == .bool(true) {
      throw SourceProblems("script", "ran longer than \(timeout) and was stopped")
    }
    if let error = envelope["error"]?.string {
      throw SourceProblems("script", error + (envelope["line"]?.int.map { " (line \($0))" } ?? ""))
    }
    guard let value = envelope["value"], value != .null else {
      throw SourceProblems(call.name, "returned nothing")
    }
    return value
  }

  private static func input(_ call: Call, now: Timestamp) throws(SourceProblems) -> String {
    var members: [String: JSONValue] = ["now": .integer(now.millisecondsSince1970)]
    do {
      switch call {
      case .requests(let state): members["state"] = state ?? .null
      case .parse(let responses): members["responses"] = try JSONValue(encoding: responses)
      }
    } catch {
      throw SourceProblems("sandbox", "could not hand the script its input: \(error)")
    }
    return JSONValue.object(members).text
  }

  private func load() async -> Bool {
    await withCheckedContinuation { continuation in
      loading = continuation
      if webView?.loadHTMLString(Self.page, baseURL: nil) == nil { finishLoading(false) }
    }
  }

  private func evaluate(_ body: String, input: String, timeout: Duration) async throws(SourceProblems) -> String {
    let result = await withCheckedContinuation { continuation in
      answer = continuation
      Task { [weak self, weak webView] in
        do {
          let value = try await webView?.callAsyncJavaScript(
            body, arguments: ["inputText": input], in: nil, contentWorld: .page)
          self?.respond(value.flatMap { $0 as? String }.map { .success($0) } ?? .failure(Self.nothing))
        } catch {
          self?.respond(.failure(Self.problems(error)))
        }
      }
      Task { [weak self] in
        try? await Task.sleep(for: timeout)
        self?.respond(.failure(SourceProblems("script", "ran longer than \(timeout) and was stopped")))
      }
    }
    return try result.get()
  }

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

  /// Drops the page, and with it whatever the script is still doing.
  private func close() {
    webView?.stopLoading()
    webView?.navigationDelegate = nil
    webView = nil
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
    finishLoading(false)
    respond(.failure(SourceProblems("script", "its page stopped")))
  }
}

extension ParseSandbox.Call {
  var name: String {
    switch self {
    case .requests: "requests"
    case .parse: "parse"
    }
  }
}
