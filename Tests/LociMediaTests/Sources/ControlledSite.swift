import Foundation
import Network
import Synchronization

/// A site on a free port of `127.0.0.1` that answers what the test sets and records every request: its
/// method, path and Cookie header.
final class ControlledSite: Sendable {
  struct Answer: Sendable {
    var status = 200
    var headers: [String: String] = ["Content-Type": "text/html; charset=utf-8"]
    var body = ""
  }

  struct Request: Hashable, Sendable {
    let method: String
    let path: String
    let cookie: String?
  }

  private let listener: NWListener
  private let state = Mutex<(answers: [String: Answer], requests: [Request])>(([:], []))
  let port: UInt16

  static func start() async throws -> ControlledSite {
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
    return ControlledSite(listener: listener, port: port)
  }

  private init(listener: NWListener, port: UInt16) {
    self.listener = listener
    self.port = port
    listener.newConnectionHandler = { [self] connection in self.answer(connection) }
  }

  /// On `host`, which may be `127.0.0.1` or `localhost`: the same server under two sites.
  func url(_ path: String, host: String = "127.0.0.1") -> URL { URL(string: "http://\(host):\(port)\(path)")! }

  func set(_ path: String, _ answer: Answer) {
    state.withLock { $0.answers[path] = answer }
  }

  var requests: [Request] { state.withLock { $0.requests } }

  func stop() { listener.cancel() }

  private func answer(_ connection: NWConnection) {
    connection.start(queue: .global())
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, _, _ in
      let head = String(decoding: data ?? Data(), as: UTF8.self).components(separatedBy: "\r\n")
      let words = (head.first ?? "").split(separator: " ").map(String.init)
      let cookie = head.first { $0.lowercased().hasPrefix("cookie:") }.map {
        $0.dropFirst("cookie:".count).trimmingCharacters(in: .whitespaces)
      }
      let path = words.count > 1 ? words[1] : "/"
      let answer = state.withLock { state in
        state.requests.append(Request(method: words.first ?? "", path: path, cookie: cookie))
        return state.answers[path] ?? Answer(status: 404, body: "<title>Not found</title>")
      }
      let body = Data(answer.body.utf8)
      let fields = answer.headers.map { "\($0.key): \($0.value)\r\n" }.joined()
      let reply =
        "HTTP/1.1 \(answer.status) X\r\n\(fields)Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
      connection.send(content: Data(reply.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
  }
}
