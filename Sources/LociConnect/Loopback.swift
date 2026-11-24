import Foundation
import Network

/// Where the browser comes back to after a sign-in.
public protocol CallbackReceiver: Sendable {
  func open() async throws(ConnectError) -> any CallbackWait
}

/// One redirect being listened at, until a callback comes or it is closed.
public protocol CallbackWait: Sendable {
  /// `http://127.0.0.1:<port>/callback`, registered with the authorization server for this connection only.
  var redirect: URL { get }
  /// The first request carrying `code` or `error`. Throws once closed.
  func callback() async throws(ConnectError) -> URL
  func close() async
}

/// Listens on 127.0.0.1 only, at a port the system picks, so no other machine can reach it and the Mac
/// asks nothing of the firewall. Each request is answered with a short page saying to go back to Loci.
public struct LoopbackReceiver: CallbackReceiver {
  public init() {}

  public func open() async throws(ConnectError) -> any CallbackWait {
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
    let running = Task {
      try? await listener.run { connection in
        guard let target = try await Self.target(on: connection) else { return }
        let page = Data(Self.page.utf8)
        let head =
          "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.count)\r\n"
          + "Connection: close\r\n\r\n"
        try await connection.send(Data(head.utf8) + page, endOfStream: true)
        if let url = URL(string: "http://127.0.0.1\(target)"), Self.isCallback(url) { callback.yield(url) }
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
    return LoopbackWait(redirect: redirect, callbacks: callbacks, running: running)
  }

  static let page =
    "<!doctype html><meta charset=utf-8><title>Loci</title>"
    + "<p style=\"font: 15px -apple-system; margin: 3em\">已连接，可以回到 Loci 了。 Connected. You can go back to Loci.</p>"

  /// Whether the request is the authorization server sending the browser back.
  static func isCallback(_ url: URL) -> Bool {
    let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? []
    return names.contains("code") || names.contains("error")
  }

  /// The path and query of the request line, once the head has come.
  private static func target(on connection: NetworkConnection<TCP>) async throws -> String? {
    var head = Data()
    while head.count < 65_536 {
      let message = try await connection.receive(atLeast: 1, atMost: 65_536)
      head.append(message.content)
      if let text = String(data: head, encoding: .utf8), text.contains("\r\n\r\n") || text.contains("\n\n") {
        let line = text.split(whereSeparator: \.isNewline).first ?? ""
        let parts = line.split(separator: " ")
        return parts.count >= 2 ? String(parts[1]) : nil
      }
    }
    return nil
  }
}

actor LoopbackWait: CallbackWait {
  nonisolated let redirect: URL
  private var callbacks: AsyncStream<URL>.AsyncIterator
  private let running: Task<Void, Never>

  init(redirect: URL, callbacks: AsyncStream<URL>, running: Task<Void, Never>) {
    self.redirect = redirect
    self.callbacks = callbacks.makeAsyncIterator()
    self.running = running
  }

  func callback() async throws(ConnectError) -> URL {
    var waiting = callbacks
    let url = await waiting.next(isolation: self)
    callbacks = waiting
    guard let url else { throw .callback("the sign-in was closed") }
    return url
  }

  func close() {
    running.cancel()
  }
}
