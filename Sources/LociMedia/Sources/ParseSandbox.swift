import Foundation
import LociModel

/// Runs a source's script on a page no one sees, made for that one call and dropped after it.
///
/// One deadline holds loading the page, running the script and stopping it. A run that goes past it is
/// stopped by the page ending its worker. If the page itself does not answer by the deadline, or the fetch is
/// cancelled, the page is asked to end its worker again and again, for at most `stopping`; then the page is
/// closed whatever it is doing, and its process with it. The run returns only after that, so the fetch it
/// belongs to holds its place until the script is stopped, and never longer than the deadline and `stopping`.
///
/// What holds the script in: it runs in a worker the page starts, and the page ends the worker when its time
/// is up, because a script stuck in a loop on the page itself would stop the page answering. The app's
/// prelude takes `fetch`, `XMLHttpRequest`, `WebSocket`, `importScripts` and storage away inside the worker;
/// what the page lets load is `WebSandboxPage`'s.
@MainActor
enum ParseSandbox {
  /// What the script is asked for.
  enum Call {
    case requests(state: JSONValue?)
    case parse(responses: [SourceResponse])
  }

  /// How long past the script's own time the page has to answer before it is asked to end its worker.
  static let grace: Duration = .seconds(2)
  /// How long the page is asked to end its worker before it is closed.
  static let stopping: Duration = .seconds(3)

  static let cancelled = SourceProblems("script", "its fetch was cancelled, and it was stopped")

  /// What the script's `requests(state)` or `parse(responses, now)` returned, as JSON.
  /// `ended` is told, before this returns, that the page is closed and its worker ended, or the page closed.
  static func run(
    _ script: String, _ call: Call, now: Timestamp, timeout: Duration, stopping: Duration = stopping,
    page open: () -> any SandboxPage = { WebSandboxPage() }, ended: @Sendable () -> Void = {}
  ) async throws(SourceProblems) -> JSONValue {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout + grace
    let page = open()
    defer {
      page.close()
      ended()
    }
    guard await within(deadline, otherwise: false, cancelled: false, page.load) else {
      if Task.isCancelled { throw cancelled }
      throw SourceProblems("sandbox", "the page to run the script in did not load in time")
    }
    let left = max(.zero, deadline - clock.now - grace)
    let body = try Self.page(script, call, timeout: left)
    let input = try input(call, now: now)
    let result = await within(deadline, otherwise: .failure(overdue), cancelled: .failure(cancelled)) {
      await page.evaluate(body, input: input)
    }
    if case .failure(let problems) = result, problems == overdue || problems == cancelled {
      let by = clock.now + stopping
      let stopped = await Task { await stop(page, by: by) }.value
      if problems == cancelled { throw cancelled }
      throw stopped
        ? SourceProblems("script", "ran longer than \(timeout) and was stopped")
        : SourceProblems("script", "ran longer than \(timeout); its page did not stop it and was closed")
    }
    return try answer(try result.get(), call: call, timeout: timeout)
  }

  /// Asks the page to end its worker until it says it has, or `deadline` passes; whether it said so.
  private static func stop(_ page: any SandboxPage, by deadline: ContinuousClock.Instant) async -> Bool {
    let clock = ContinuousClock()
    while clock.now < deadline {
      let asked = clock.now
      if await within(min(deadline, asked + .milliseconds(500)), otherwise: false, cancelled: nil, page.endWorker) {
        return true
      }
      try? await Task.sleep(until: min(deadline, asked + .milliseconds(100)))
    }
    return false
  }

  /// What `work` gives, or `otherwise` once `deadline` passes first, or `cancelled` as soon as the task is
  /// cancelled, when given. `work` is left to the page's closing to answer.
  private static func within<Value: Sendable>(
    _ deadline: ContinuousClock.Instant, otherwise: Value, cancelled: Value?,
    _ work: @escaping @MainActor () async -> Value
  ) async -> Value {
    let first = First<Value>()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        first.waiting = continuation
        Task { first.give(await work()) }
        first.timer = Task {
          try? await Task.sleep(until: deadline)
          first.give(otherwise)
        }
      }
    } onCancel: {
      if let cancelled { Task { @MainActor in first.give(cancelled) } }
    }
  }

  /// The page's side: starts the worker, hands it the input, and ends it when it answers or runs out of time.
  /// The worker is kept on the page until it is ended, so it can be ended from outside too.
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
      window.lociWorker = worker;
      return await new Promise((resolve) => {
        const end = (answer) => {
          clearTimeout(timer); worker.terminate(); window.lociWorker = null; resolve(JSON.stringify(answer));
        };
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

  /// The page did not answer by the deadline.
  private static let overdue = SourceProblems("script", "ran past its time and was stopped")

  private static let nothing = SourceProblems("script", "returned nothing")
}

/// The first of several answers, given to whoever waits for it; the rest are dropped.
@MainActor
private final class First<Value: Sendable> {
  var waiting: CheckedContinuation<Value, Never>?
  var timer: Task<Void, Never>?

  func give(_ value: Value) {
    timer?.cancel()
    timer = nil
    let continuation = waiting
    waiting = nil
    continuation?.resume(returning: value)
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
