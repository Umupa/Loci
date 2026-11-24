/// Why a connector could not connect, renew its sign-in, or answer.
public enum ConnectError: Error, Hashable, Sendable {
  /// The MCP server wants a sign-in, or a fresh one.
  case unauthorized
  /// The sign-in ran out and cannot be renewed: the person connects again.
  case needsReconnecting(String)
  /// The server cannot be connected this way: no metadata, no S256, no registration.
  case unsupported(String)
  /// The browser came back without a code: refused, another state, or never.
  case callback(String)
  /// The server answered with something else than asked.
  case server(String)
  /// It could not be reached.
  case offline(String)

  public var reason: String {
    switch self {
    case .unauthorized: "the server wants a sign-in"
    case .needsReconnecting(let reason), .unsupported(let reason), .callback(let reason), .server(let reason),
      .offline(let reason):
      reason
    }
  }
}
