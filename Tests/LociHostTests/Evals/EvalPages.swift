import Foundation
import Network
import Synchronization

/// The pages a schedule reads in an eval, served on a free port of `127.0.0.1` so no run reaches the
/// internet. What each path answers changes from day to day; the server counts what was asked.
final class EvalPages: Sendable {
  private let listener: NWListener
  private let state = Mutex<(pages: [String: String], requests: [String])>(([:], []))
  let port: UInt16

  /// Starts listening; the port is known once this returns.
  static func start() async throws -> EvalPages {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters)
    let port = try await withCheckedThrowingContinuation { (ready: CheckedContinuation<UInt16, any Error>) in
      let once = Mutex(false)
      listener.stateUpdateHandler = { state in
        let first = once.withLock { done in
          defer { done = true }
          return !done
        }
        switch state {
        case .ready where first: ready.resume(returning: listener.port?.rawValue ?? 0)
        case .failed(let error) where first: ready.resume(throwing: error)
        default: break
        }
      }
      listener.newConnectionHandler = { _ in }
      listener.start(queue: .global())
    }
    return EvalPages(listener: listener, port: port)
  }

  private init(listener: NWListener, port: UInt16) {
    self.listener = listener
    self.port = port
    listener.newConnectionHandler = { [self] connection in self.answer(connection) }
  }

  func url(_ path: String) -> String { "http://127.0.0.1:\(port)\(path)" }

  /// From now on each path answers this HTML.
  func show(_ pages: [String: String]) {
    state.withLock { $0.pages = pages }
  }

  /// The paths asked for since the last call.
  func takeRequests() -> [String] {
    state.withLock { state in
      defer { state.requests = [] }
      return state.requests
    }
  }

  func stop() {
    listener.cancel()
  }

  private func answer(_ connection: NWConnection) {
    connection.start(queue: .global())
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, _, _ in
      let line = String(decoding: data ?? Data(), as: UTF8.self).split(separator: "\r\n").first ?? ""
      let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
      let page = state.withLock { state in
        state.requests.append(path)
        return state.pages[path.split(separator: "?").first.map(String.init) ?? path]
      }
      let body = Data((page ?? "<!doctype html><title>Not found</title>").utf8)
      let head =
        "HTTP/1.1 \(page == nil ? "404 Not Found" : "200 OK")\r\nContent-Type: text/html; charset=utf-8\r\n"
        + "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
      connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
  }
}
