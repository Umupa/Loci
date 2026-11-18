import CryptoKit
import Foundation

/// The relay (alma-relay) that lets two Macs on different networks reach each other: each Mac registers
/// its route token's hash as an agent, and others open `/c/<token>/__loci__` as clients.
public struct Relay: Hashable, Sendable {
  /// `wss://` or `ws://`, without a path.
  public let address: URL
  /// The relay's registration key, if it wants one.
  public let registrationKey: String?

  public init(address: URL, registrationKey: String?) {
    self.address = address
    self.registrationKey = registrationKey
  }

  /// The only path a Mac serves; everything else the relay forwards is refused.
  public static let lociPath = "/__loci__"
  /// The newest agent protocol Loci speaks.
  static let newestProtocol = 3

  func agentURL(tokenHash: String) -> URL {
    address.appending(path: "agent").appending(queryItems: [URLQueryItem(name: "th", value: tokenHash)])
  }

  func clientURL(token: String) -> URL {
    address.appending(path: "c").appending(path: token).appending(path: String(Self.lociPath.dropFirst()))
  }

  /// What the relay keeps: the hex SHA-256 of the token, never the token.
  public static func tokenHash(of token: String) -> String {
    SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

/// What a registered agent reports.
public enum AgentEvent: Sendable {
  /// The relay accepted the registration, speaking this protocol.
  case registered(proto: Int)
  /// Another Mac opened `/__loci__`.
  case connection(any MessageSocket)
  /// The relay connection was lost; the agent dials again after a pause.
  case disconnected(SocketError)
  /// The agent will not dial again. The stream ends after this.
  case stopped(AgentStop)
}

public enum AgentStop: Error, Hashable, Sendable {
  /// Another agent registered the same token, which the relay tells with close code 4000. Dialing again
  /// would only push it out in turn, so the agent stops.
  case displaced
  /// The relay refused the registration key (close code 4003 or 4401).
  case keyRejected
  /// The relay refused the token hash (close code 4002).
  case badTokenHash
}

/// Opens a connection to a Mac through the relay, as a client.
public enum RelayClient {
  public static func open(
    _ relay: Relay, token: String, dialer: any SocketDialer, heartbeat: Heartbeat = Heartbeat(),
    clock: any Clock<Duration> = ContinuousClock()
  ) async throws(SocketError) -> any MessageSocket {
    let url = relay.clientURL(token: token)
    let socket = try await within(heartbeat.dialTimeout, on: clock) { () async throws(SocketError) in
      try await dialer.dial(url)
    }
    let kept = KeptAlive(socket, heartbeat: heartbeat, clock: clock)
    await kept.start()
    return kept
  }
}
