import CryptoKit
import Foundation
import LociModel

/// A public client registered for one connection, with the loopback redirect it was registered with.
public struct Registration: Hashable, Sendable {
  public let discovery: Discovery
  public let clientID: String
  public let redirect: URL
}

/// An authorization the browser is to finish. Only `OAuth.authorize` makes one, with a fresh verifier and state.
public struct PendingAuthorization: Hashable, Sendable {
  public let registration: Registration
  let verifier: String
  let state: String
  /// The page to open in the browser.
  public let url: URL

  /// The code the browser came back with, when the callback carries this authorization's state and no error.
  public func code(from callback: URL) throws(ConnectError) -> AuthorizationCode {
    let fields = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func field(_ name: String) -> String? { fields.first { $0.name == name }?.value }
    if let error = field("error") {
      throw .callback(field("error_description").map { "\(error): \($0)" } ?? error)
    }
    guard field("state") == state else { throw .callback("the browser came back from another sign-in") }
    guard let code = field("code"), !code.isEmpty else { throw .callback("the browser came back without a code") }
    return AuthorizationCode(pending: self, code: code)
  }
}

/// A code the browser came back with, for the authorization it belongs to.
public struct AuthorizationCode: Hashable, Sendable {
  public let pending: PendingAuthorization
  let code: String
}

/// What a connector signs in with: kept in the keychain, never given to the companion.
public struct MCPCredential: Hashable, Codable, Sendable {
  public let mcp: URL
  public let resource: String
  public let tokenEndpoint: URL
  public let clientID: String
  public let accessToken: String
  public let refreshToken: String?
  public let expiresAt: Timestamp?
  /// The account, when the token response says it.
  public let account: String?

  public init(
    mcp: URL, resource: String, tokenEndpoint: URL, clientID: String, accessToken: String, refreshToken: String?,
    expiresAt: Timestamp?, account: String?
  ) {
    self.mcp = mcp
    self.resource = resource
    self.tokenEndpoint = tokenEndpoint
    self.clientID = clientID
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
    self.account = account
  }

  /// Whether the access token runs out within a minute of `now`.
  public func expires(by now: Timestamp) -> Bool {
    guard let expiresAt else { return false }
    return expiresAt.millisecondsSince1970 - now.millisecondsSince1970 < 60_000
  }
}

/// Signing in with OAuth 2.1, one step at a time: each step takes what the step before gave, so no step can
/// be skipped.
public struct OAuth: Sendable {
  let http: any HTTPClient
  /// Random bytes for the PKCE verifier and the state.
  let randomBytes: @Sendable (Int) -> Data

  public init(http: any HTTPClient, randomBytes: @escaping @Sendable (Int) -> Data) {
    self.http = http
    self.randomBytes = randomBytes
  }

  public func discover(_ mcp: URL, scope: String? = nil) async throws(ConnectError) -> Access {
    try await Discoverer(http: http).discover(mcp, scope: scope)
  }

  /// Registers a public client for this connection only, with `redirect` as its one redirect.
  public func register(_ discovery: Discovery, redirect: URL) async throws(ConnectError) -> Registration {
    let body = JSONValue.object([
      "client_name": .string("Loci"),
      "redirect_uris": .array([.string(redirect.absoluteString)]),
      "grant_types": .array([.string("authorization_code"), .string("refresh_token")]),
      "response_types": .array([.string("code")]),
      "token_endpoint_auth_method": .string("none"),
    ])
    let response = try await http.send(
      HTTPRequest(
        "POST", discovery.server.registrationEndpoint,
        headers: ["Content-Type": "application/json", "Accept": "application/json"], body: Data(body.text.utf8)))
    guard (200..<300).contains(response.status), let client = response.json?["client_id"]?.string else {
      throw .unsupported("the server would not register Loci (HTTP \(response.status))")
    }
    return Registration(discovery: discovery, clientID: client, redirect: redirect)
  }

  public func authorize(_ registration: Registration) -> PendingAuthorization {
    let verifier = Self.base64URL(randomBytes(32))
    let state = Self.base64URL(randomBytes(16))
    let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    let discovery = registration.discovery
    var fields = [
      "response_type": "code", "client_id": registration.clientID, "redirect_uri": registration.redirect.absoluteString,
      "code_challenge": challenge, "code_challenge_method": "S256", "state": state,
      "resource": discovery.resource.resource,
    ]
    if let scope = discovery.resource.scope { fields["scope"] = scope }
    var components = URLComponents(url: discovery.server.authorizationEndpoint, resolvingAgainstBaseURL: false)
    let existing = components?.queryItems ?? []
    components?.queryItems =
      existing + fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    return PendingAuthorization(
      registration: registration, verifier: verifier, state: state,
      url: components?.url ?? discovery.server.authorizationEndpoint)
  }

  public func exchange(_ code: AuthorizationCode, now: Timestamp) async throws(ConnectError) -> MCPCredential {
    let registration = code.pending.registration
    let discovery = registration.discovery
    let response = try await http.send(
      .form(
        discovery.server.tokenEndpoint,
        [
          "grant_type": "authorization_code", "code": code.code, "redirect_uri": registration.redirect.absoluteString,
          "client_id": registration.clientID, "code_verifier": code.pending.verifier,
          "resource": discovery.resource.resource,
        ]))
    guard response.status == 200, let tokens = response.json, let access = tokens["access_token"]?.string else {
      throw .callback("the server would not give a token (HTTP \(response.status))")
    }
    return MCPCredential(
      mcp: discovery.resource.mcp, resource: discovery.resource.resource, tokenEndpoint: discovery.server.tokenEndpoint,
      clientID: registration.clientID, accessToken: access, refreshToken: tokens["refresh_token"]?.string,
      expiresAt: Self.expiry(tokens, now: now), account: Self.account(tokens))
  }

  /// A new access token. The refresh token is replaced when the server rotates it.
  public func refresh(_ credential: MCPCredential, now: Timestamp) async throws(ConnectError) -> MCPCredential {
    guard let refresh = credential.refreshToken else { throw .needsReconnecting("the sign-in ran out") }
    let response = try await http.send(
      .form(
        credential.tokenEndpoint,
        [
          "grant_type": "refresh_token", "refresh_token": refresh, "client_id": credential.clientID,
          "resource": credential.resource,
        ]))
    guard response.status == 200, let tokens = response.json, let access = tokens["access_token"]?.string else {
      if (400..<500).contains(response.status) { throw .needsReconnecting("the sign-in ran out") }
      throw .server("renewing the sign-in failed (HTTP \(response.status))")
    }
    return MCPCredential(
      mcp: credential.mcp, resource: credential.resource, tokenEndpoint: credential.tokenEndpoint,
      clientID: credential.clientID, accessToken: access, refreshToken: tokens["refresh_token"]?.string ?? refresh,
      expiresAt: Self.expiry(tokens, now: now), account: credential.account ?? Self.account(tokens))
  }

  private static func expiry(_ tokens: JSONValue, now: Timestamp) -> Timestamp? {
    tokens["expires_in"]?.number.map { Timestamp(millisecondsSince1970: now.millisecondsSince1970 + Int64($0 * 1000)) }
  }

  /// The account, from the few places servers put it in a token response.
  private static func account(_ tokens: JSONValue) -> String? {
    tokens["account"]?.string ?? tokens["user"]?["name"]?.string ?? tokens["owner"]?["user"]?["name"]?.string
      ?? tokens["workspace_name"]?.string ?? tokens["email"]?.string
  }

  static func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
  }
}
