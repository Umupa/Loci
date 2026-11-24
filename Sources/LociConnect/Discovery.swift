import Foundation
import LociModel

/// The MCP server as RFC 9728 describes it: what to ask a token for, and who gives it.
public struct ProtectedResource: Hashable, Sendable {
  public let mcp: URL
  /// The `resource` every authorization and token request carries (RFC 8707).
  public let resource: String
  public let scope: String?
  public let issuer: URL
}

/// An authorization server Loci can sign in with: it takes PKCE with S256 and registers clients itself.
public struct AuthorizationServer: Hashable, Sendable {
  public let issuer: URL
  public let authorizationEndpoint: URL
  public let tokenEndpoint: URL
  public let registrationEndpoint: URL

  /// Refuses a server that does not offer S256, or that has no registration endpoint.
  public init(metadata: JSONValue, issuer: URL) throws(ConnectError) {
    guard let authorize = metadata["authorization_endpoint"]?.string.flatMap(URL.init(string:)),
      let token = metadata["token_endpoint"]?.string.flatMap(URL.init(string:))
    else { throw .unsupported("the authorization server names no authorization or token endpoint") }
    let methods = metadata["code_challenge_methods_supported"]?.array?.compactMap(\.string) ?? []
    guard methods.contains("S256") else { throw .unsupported("the authorization server does not offer PKCE with S256") }
    guard let register = metadata["registration_endpoint"]?.string.flatMap(URL.init(string:)) else {
      throw .unsupported("this server needs an app registered with it ahead; Loci cannot connect to it yet")
    }
    self.issuer = issuer
    authorizationEndpoint = authorize
    tokenEndpoint = token
    registrationEndpoint = register
  }
}

public struct Discovery: Hashable, Sendable {
  public let resource: ProtectedResource
  public let server: AuthorizationServer
}

/// What an MCP address needs: a sign-in, found as below, or none.
public enum Access: Hashable, Sendable {
  case signIn(Discovery)
  /// It answers without a sign-in and names no authorization server.
  case open
}

/// Finds out how to sign in with an MCP server. In order: the `resource_metadata` in the 401's challenge,
/// then the well-known addresses of RFC 9728, then the authorization server it names (RFC 8414, with the path
/// of an issuer inserted). A server without resource metadata is taken to be its own authorization server,
/// as the 2025-03-26 specification had it; Atlassian still works that way.
struct Discoverer: Sendable {
  let http: any HTTPClient

  func discover(_ mcp: URL, scope override: String? = nil) async throws(ConnectError) -> Access {
    let probe = try await http.send(MCPClient.initializeRequest(to: mcp, token: nil, session: nil))
    let challenge = probe.header("WWW-Authenticate") ?? ""
    var candidates: [URL] = []
    if let named = Self.parameter("resource_metadata", in: challenge).flatMap(URL.init(string:)) {
      candidates.append(named)
    }
    candidates += Self.wellKnown(mcp, "oauth-protected-resource")
    let metadata = try await firstJSON(at: candidates) { $0["authorization_servers"] != nil || $0["resource"] != nil }
    guard probe.status == 401 || metadata != nil else { return .open }
    let issuer =
      metadata?["authorization_servers"]?.array?.first?.string.flatMap(URL.init(string:)) ?? Self.origin(of: mcp)
    let scope =
      override ?? Self.parameter("scope", in: challenge)
      ?? metadata?["scopes_supported"]?.array.map { $0.compactMap(\.string).joined(separator: " ") }
    let resource = ProtectedResource(
      mcp: mcp, resource: metadata?["resource"]?.string ?? mcp.absoluteString,
      scope: scope?.isEmpty == true ? nil : scope, issuer: issuer)
    let addresses =
      Self.wellKnown(issuer, "oauth-authorization-server") + Self.wellKnown(issuer, "openid-configuration")
      + [issuer.appending(path: ".well-known/openid-configuration")]
    guard let server = try await firstJSON(at: addresses, where: { $0["authorization_endpoint"] != nil }) else {
      throw .unsupported("no authorization server metadata was found for \(mcp.host() ?? mcp.absoluteString)")
    }
    return .signIn(Discovery(resource: resource, server: try AuthorizationServer(metadata: server, issuer: issuer)))
  }

  private func firstJSON(at addresses: [URL], where fits: (JSONValue) -> Bool) async throws(ConnectError)
    -> JSONValue?
  {
    for address in addresses {
      let response = try await http.send(HTTPRequest("GET", address, headers: ["Accept": "application/json"]))
      if response.status == 200, let json = response.json, fits(json) { return json }
    }
    return nil
  }

  /// `/.well-known/<name><path>`, then `/.well-known/<name>` when there is a path.
  static func wellKnown(_ base: URL, _ name: String) -> [URL] {
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return [] }
    let path = components.path == "/" ? "" : components.path
    components.query = nil
    components.fragment = nil
    var found: [URL] = []
    components.path = "/.well-known/\(name)\(path)"
    if let url = components.url { found.append(url) }
    if !path.isEmpty {
      components.path = "/.well-known/\(name)"
      if let url = components.url { found.append(url) }
    }
    return found
  }

  static func origin(of url: URL) -> URL {
    var components = URLComponents()
    components.scheme = url.scheme
    components.host = url.host()
    components.port = url.port
    return components.url ?? url
  }

  /// A parameter of a `WWW-Authenticate` challenge, quoted or not.
  static func parameter(_ name: String, in challenge: String) -> String? {
    for match in challenge.matches(of: /([A-Za-z_]+)\s*=\s*(?:"([^"]*)"|([^\s,]+))/)
    where match.1.lowercased() == name {
      return String(match.2 ?? match.3 ?? "")
    }
    return nil
  }
}
