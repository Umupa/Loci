import Foundation
import Network

/// Where the browser comes back to after a sign-in to `service`, named as the person knows it.
public protocol CallbackReceiver: Sendable {
  func open(for service: String) async throws(ConnectError) -> any CallbackWait
}

/// One redirect being listened at, until a callback comes or it is closed.
public protocol CallbackWait: Sendable {
  /// `http://127.0.0.1:<port>/callback`, registered with the authorization server for this connection only.
  var redirect: URL { get }
  /// The first request carrying `code` or `error`. Throws once closed. The browser waits for `answer`.
  func callback() async throws(ConnectError) -> URL
  /// Tells the browser that came back what came of the sign-in; the first answer stands.
  func answer(_ outcome: SignInOutcome) async
  /// Stops listening once the browsers that came back have read their page; one still waiting is told the
  /// sign-in failed.
  func close() async
}

/// Listens on 127.0.0.1 only, at a port the system picks, so no other machine can reach it and the Mac
/// asks nothing of the firewall. The browser that comes back waits until the sign-in is done, then gets a page
/// saying what came of it.
public struct LoopbackReceiver: CallbackReceiver {
  public init() {}

  public func open(for service: String) async throws(ConnectError) -> any CallbackWait {
    let listener: NetworkListener<TCP>
    do {
      listener = try NetworkListener(
        using: .parameters { TCP() }.localEndpoint(.hostPort(host: "127.0.0.1", port: .any)))
    } catch {
      throw .offline("could not listen for the browser: \(error.localizedDescription)")
    }
    let (states, state) = AsyncStream.makeStream(of: Bool.self)
    listener.onStateUpdate { _, update in
      switch update {
      case .ready: state.yield(true)
      case .failed, .cancelled: state.yield(false)
      default: break
      }
    }
    let (callbacks, callback) = AsyncStream.makeStream(of: URL.self)
    let answers = Answers()
    let running = Task {
      try? await listener.run { connection in
        guard let request = try await Self.request(on: connection) else { return }
        guard let url = URL(string: "http://127.0.0.1\(request.target)"), Self.isCallback(url) else {
          try await Self.send(status: "404 Not Found", page: "", on: connection)
          return
        }
        await answers.expect()
        callback.yield(url)
        let page = SignInPage(
          service: service, outcome: await answers.outcome(),
          language: .init(acceptLanguage: request.acceptLanguage))
        try? await Self.send(status: "200 OK", page: page.html, on: connection)
        _ = try? await connection.receive(atLeast: 1, atMost: 1)
        await answers.replied()
      }
      state.yield(false)
      callback.finish()
    }
    var ready = false
    for await isReady in states {
      ready = isReady
      break
    }
    guard ready, let port = listener.port?.rawValue,
      let redirect = URL(string: "http://127.0.0.1:\(port)/callback")
    else {
      running.cancel()
      throw .offline("could not listen for the browser")
    }
    return LoopbackWait(redirect: redirect, callbacks: callbacks, answers: answers, running: running)
  }

  /// Sends a whole response; the browser hangs up once it has read it, as the response asks.
  private static func send(status: String, page: String, on connection: NetworkConnection<TCP>) async throws {
    let body = Data(page.utf8)
    let head =
      "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\n"
      + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
    try await connection.send(Data(head.utf8) + body, endOfStream: true)
  }

  /// Whether the request is the authorization server sending the browser back.
  static func isCallback(_ url: URL) -> Bool {
    let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? []
    return names.contains("code") || names.contains("error")
  }

  /// The path and query of the request line and the languages the browser asks for, once the head has come.
  private static func request(on connection: NetworkConnection<TCP>) async throws -> (
    target: String, acceptLanguage: String?
  )? {
    var head = Data()
    while head.count < 65_536 {
      let message = try await connection.receive(atLeast: 1, atMost: 65_536)
      head.append(message.content)
      if let text = String(data: head, encoding: .utf8), text.contains("\r\n\r\n") || text.contains("\n\n") {
        let lines = text.split(whereSeparator: \.isNewline)
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let language = lines.dropFirst().first { $0.lowercased().hasPrefix("accept-language:") }
          .map { String($0.dropFirst("accept-language:".count)).trimmingCharacters(in: .whitespaces) }
        return (String(parts[1]), language)
      }
    }
    return nil
  }
}

/// What the browsers that came back wait for: the outcome of the sign-in, the first one settled; and how many
/// are still reading their page, as stopping the listener cuts off a page half sent.
actor Answers {
  private var settled: SignInOutcome?
  private var waiting: [CheckedContinuation<SignInOutcome, Never>] = []
  private var replying = 0
  private var drained: [CheckedContinuation<Void, Never>] = []

  func expect() { replying += 1 }

  func outcome() async -> SignInOutcome {
    if let settled { return settled }
    return await withCheckedContinuation { waiting.append($0) }
  }

  func settle(_ outcome: SignInOutcome) {
    guard settled == nil else { return }
    settled = outcome
    for browser in waiting { browser.resume(returning: outcome) }
    waiting = []
  }

  /// A browser has its page and has hung up.
  func replied() {
    replying -= 1
    guard replying == 0 else { return }
    for drain in drained { drain.resume() }
    drained = []
  }

  /// Returns once no browser is still reading its page.
  func drain() async {
    guard replying > 0 else { return }
    await withCheckedContinuation { drained.append($0) }
  }
}

actor LoopbackWait: CallbackWait {
  nonisolated let redirect: URL
  private var callbacks: AsyncStream<URL>.AsyncIterator
  private let answers: Answers
  private let running: Task<Void, Never>

  init(redirect: URL, callbacks: AsyncStream<URL>, answers: Answers, running: Task<Void, Never>) {
    self.redirect = redirect
    self.callbacks = callbacks.makeAsyncIterator()
    self.answers = answers
    self.running = running
  }

  func callback() async throws(ConnectError) -> URL {
    var waiting = callbacks
    let url = await waiting.next(isolation: self)
    callbacks = waiting
    guard let url else { throw .callback("the sign-in was closed") }
    return url
  }

  func answer(_ outcome: SignInOutcome) async {
    await answers.settle(outcome)
  }

  func close() async {
    await answers.settle(.failed)
    let answers = answers
    let running = running
    Task {
      await answers.drain()
      running.cancel()
    }
  }
}
