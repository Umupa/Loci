import CryptoKit
import Foundation
import LociModel
import Testing

@testable import LociConnect

/// CN-S1, CN-S7: signing in with PKCE through a client registered for this connection, and renewing it.
struct OAuthTests {
  static let redirect = URL(string: "http://127.0.0.1:53682/callback")!
  static let now = Timestamp(millisecondsSince1970: 1_763_337_600_000)

  private func pending(_ web: FakeWeb) async throws -> PendingAuthorization {
    Servers.notionLike(web)
    let oauth = OAuth(http: web, randomBytes: Servers.bytes)
    guard case .signIn(let discovery) = try await oauth.discover(Servers.mcp) else { throw ConnectError.server("open") }
    return oauth.authorize(try await oauth.register(discovery, redirect: Self.redirect))
  }

  private func fields(_ url: URL) -> [String: String] {
    Dictionary(
      (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    ) { first, _ in first }
  }

  @Test func registeringAsksForAPublicClientWithTheLoopbackRedirect() async throws {
    let web = FakeWeb()
    _ = try await pending(web)

    let registered = try #require(web.requests.first { $0.url.path() == "/register" })
    let body = try #require(registered.body.flatMap { JSONValue(parsing: String(decoding: $0, as: UTF8.self)) })
    #expect(body["token_endpoint_auth_method"] == .string("none"))
    #expect(body["redirect_uris"] == .array([.string(Self.redirect.absoluteString)]))
  }

  @Test func theAuthorizationAddressCarriesS256TheStateAndTheResource() async throws {
    let pending = try await pending(FakeWeb())
    let fields = fields(pending.url)
    let verifier = OAuth.base64URL(Servers.bytes(32))

    #expect(pending.url.absoluteString.hasPrefix("https://mcp.example.com/authorize?"))
    #expect(fields["code_challenge_method"] == "S256")
    #expect(fields["code_challenge"] == OAuth.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))))
    #expect(fields["state"] == OAuth.base64URL(Servers.bytes(16)))
    #expect(fields["resource"] == "https://mcp.example.com/mcp")
    #expect(fields["client_id"] == "client-1" && fields["redirect_uri"] == Self.redirect.absoluteString)
    #expect(fields["scope"] == "read")
  }

  @Test func aCallbackWithAnotherStateIsRefused() async throws {
    let pending = try await pending(FakeWeb())
    let forged = try #require(URL(string: "http://127.0.0.1:53682/callback?code=abc&state=other"))

    #expect(throws: ConnectError.callback("the browser came back from another sign-in")) {
      try pending.code(from: forged)
    }
  }

  @Test func aCallbackWithAnErrorSaysWhy() async throws {
    let pending = try await pending(FakeWeb())
    let denied = try #require(URL(string: "http://127.0.0.1:53682/callback?error=access_denied&error_description=No"))

    #expect(throws: ConnectError.callback("access_denied: No")) { try pending.code(from: denied) }
  }

  @Test func theCodeIsExchangedWithTheVerifierAndTheResource() async throws {
    let web = FakeWeb()
    let pending = try await pending(web)
    web.json(
      "POST", "https://mcp.example.com/token",
      #"{ "access_token": "at-1", "refresh_token": "rt-1", "expires_in": 3600, "workspace_name": "Umi" }"#)
    let callback = try #require(
      URL(string: "http://127.0.0.1:53682/callback?code=abc&state=\(fields(pending.url)["state"] ?? "")"))

    let credential = try await OAuth(http: web, randomBytes: Servers.bytes).exchange(
      try pending.code(from: callback), now: Self.now)

    let sent = FakeWeb.form(try #require(web.requests.last))
    #expect(sent["code_verifier"] == OAuth.base64URL(Servers.bytes(32)))
    #expect(sent["resource"] == "https://mcp.example.com/mcp" && sent["code"] == "abc")
    #expect(sent["redirect_uri"] == Self.redirect.absoluteString)
    #expect(credential.accessToken == "at-1" && credential.refreshToken == "rt-1" && credential.account == "Umi")
    #expect(credential.expiresAt == Timestamp(millisecondsSince1970: Self.now.millisecondsSince1970 + 3_600_000))
  }

  static func credential(refresh: String?) -> MCPCredential {
    MCPCredential(
      mcp: Servers.mcp, resource: Servers.mcp.absoluteString,
      tokenEndpoint: URL(string: "https://mcp.example.com/token")!, clientID: "client-1", accessToken: "old",
      refreshToken: refresh, expiresAt: now, account: nil)
  }

  @Test func refreshingKeepsARotatedRefreshToken() async throws {
    let web = FakeWeb()
    web.json(
      "POST", "https://mcp.example.com/token", #"{ "access_token": "new", "refresh_token": "rt-2", "expires_in": 60 }"#)

    let renewed = try await OAuth(http: web, randomBytes: Servers.bytes).refresh(
      Self.credential(refresh: "rt-1"), now: Self.now)

    #expect(renewed.accessToken == "new" && renewed.refreshToken == "rt-2")
    #expect(FakeWeb.form(try #require(web.requests.last))["grant_type"] == "refresh_token")
  }

  @Test func aRefusedRefreshMeansReconnecting() async {
    let web = FakeWeb()
    web.json("POST", "https://mcp.example.com/token", #"{ "error": "invalid_grant" }"#, status: 400)

    await #expect(throws: ConnectError.needsReconnecting("the sign-in ran out")) {
      try await OAuth(http: web, randomBytes: Servers.bytes).refresh(Self.credential(refresh: "rt-1"), now: Self.now)
    }
  }

  @Test func withoutARefreshTokenAnExpiredSignInMeansReconnecting() async {
    await #expect(throws: ConnectError.needsReconnecting("the sign-in ran out")) {
      try await OAuth(http: FakeWeb(), randomBytes: Servers.bytes).refresh(Self.credential(refresh: nil), now: Self.now)
    }
    #expect(Self.credential(refresh: nil).expires(by: Self.now))
  }
}
