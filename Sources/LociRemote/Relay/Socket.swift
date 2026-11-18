import Foundation

/// One message of a WebSocket.
public enum SocketMessage: Hashable, Sendable {
  case text(String)
  case binary(Data)
}

/// Why a socket stopped or could not be opened.
public enum SocketError: Error, Hashable, Sendable {
  /// The other end closed it, with the WebSocket close code.
  case closed(code: Int)
  /// The relay has no Mac registered under that token: it is asleep, quit, or offline.
  case notOnRelay
  /// The relay refused the connection with this HTTP status.
  case refused(status: Int)
  /// Nothing was heard within the heartbeat's patience, or the dial took too long.
  case timedOut
  /// The network failed, with the system's reason.
  case failed(String)
}

/// A bidirectional message stream: a WebSocket to the relay, or one bridged socket of a phone-side client
/// inside the agent's connection.
public protocol MessageSocket: Sendable {
  func send(_ message: SocketMessage) async throws(SocketError)
  /// The next message. Throws once the socket is closed, and from then on.
  func receive() async throws(SocketError) -> SocketMessage
  func close(code: Int) async
}

/// A real WebSocket, which can also be pinged.
public protocol WebSocket: MessageSocket {
  /// Returns when the pong arrives.
  func ping() async throws(SocketError)
}

/// Opens WebSockets. The app dials the network; tests dial an in-process relay.
public protocol SocketDialer: Sendable {
  func dial(_ url: URL) async throws(SocketError) -> any WebSocket
}
