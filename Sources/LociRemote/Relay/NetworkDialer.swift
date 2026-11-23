import Foundation

/// Dials real WebSockets with `URLSession`. A dial returns once the relay has answered a ping, so a refused
/// upgrade (a Mac not on the relay, a bad path) is an error of the dial and not of the first message.
public struct NetworkDialer: SocketDialer {
  private let session: URLSession

  public init(session: URLSession = URLSession(configuration: .ephemeral)) {
    self.session = session
  }

  public func dial(_ url: URL) async throws(SocketError) -> any WebSocket {
    let task = session.webSocketTask(with: url)
    task.maximumMessageSize = 32 << 20
    task.resume()
    let socket = NetworkSocket(task)
    let failure: SocketError? = await withTaskCancellationHandler {
      do throws(SocketError) {
        try await socket.ping()
        return nil
      } catch {
        return error
      }
    } onCancel: {
      task.cancel()
    }
    if let failure {
      task.cancel()
      throw Self.refusal(of: task) ?? failure
    }
    return socket
  }

  private static func refusal(of task: URLSessionWebSocketTask) -> SocketError? {
    guard let status = (task.response as? HTTPURLResponse)?.statusCode, status != 101 else { return nil }
    return status == 502 ? .notOnRelay : .refused(status: status)
  }
}

/// A `URLSessionWebSocketTask` as a `WebSocket`.
final class NetworkSocket: WebSocket {
  private let task: URLSessionWebSocketTask

  init(_ task: URLSessionWebSocketTask) {
    self.task = task
  }

  func send(_ message: SocketMessage) async throws(SocketError) {
    do {
      switch message {
      case .text(let text): try await task.send(.string(text))
      case .binary(let data): try await task.send(.data(data))
      }
    } catch {
      throw failure(error)
    }
  }

  func receive() async throws(SocketError) -> SocketMessage {
    do {
      switch try await task.receive() {
      case .string(let text): return .text(text)
      case .data(let data): return .binary(data)
      @unknown default: return .binary(Data())
      }
    } catch {
      throw failure(error)
    }
  }

  func close(code: Int) async {
    task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: nil)
  }

  func ping() async throws(SocketError) {
    try await ping(sending: task.sendPing)
  }

  func ping(sending sendPing: (@escaping @Sendable ((any Error)?) -> Void) -> Void) async throws(SocketError) {
    let pong = AsyncThrowingStream<Never, any Error> { completion in
      sendPing { completion.finish(throwing: $0) }
    }
    var waiting = pong.makeAsyncIterator()
    do {
      _ = try await waiting.next()
      try Task.checkCancellation()
    } catch {
      throw failure(error)
    }
  }

  private func failure(_ error: any Error) -> SocketError {
    if task.closeCode != .invalid { return .closed(code: task.closeCode.rawValue) }
    return .failed(error.localizedDescription)
  }
}
