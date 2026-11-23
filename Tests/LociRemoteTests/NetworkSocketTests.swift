import Foundation
import Testing

@testable import LociRemote

struct NetworkSocketTests {
  @Test("A successful ping ignores a second callback reporting a lost connection")
  func keepsTheFirstPong() async throws {
    let socket = try socket()
    try await socket.ping { pong in
      pong(nil)
      pong(URLError(.networkConnectionLost))
    }
  }

  @Test("A failed ping reports the connection error even if a second callback reports success")
  func keepsTheFirstFailure() async throws {
    let socket = try socket()
    let failure = URLError(.networkConnectionLost)
    await #expect(throws: SocketError.failed(failure.localizedDescription)) {
      try await socket.ping { pong in
        pong(failure)
        pong(nil)
      }
    }
  }

  @Test("Cancelling a ping before the pong arrives reports a failure")
  func cancelsWhileWaiting() async throws {
    let socket = try socket()
    let ping = Task {
      try await socket.ping { _ in
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }
    await #expect(throws: SocketError.failed(CancellationError().localizedDescription)) {
      try await ping.value
    }
  }

  private func socket() throws -> NetworkSocket {
    let url = try #require(URL(string: "ws://127.0.0.1"))
    return NetworkSocket(URLSession.shared.webSocketTask(with: url))
  }
}
