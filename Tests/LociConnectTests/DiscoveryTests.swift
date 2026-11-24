import Foundation
import Testing

@testable import LociConnect

/// CN-S1: Loci finds how to sign in with an MCP server on its own, the way each kind of server says it.
struct DiscoveryTests {
  private func discover(_ web: FakeWeb, _ mcp: URL = Servers.mcp, scope: String? = nil) async throws -> Discovery {
    guard
      case .signIn(let discovery) = try await OAuth(http: web, randomBytes: Servers.bytes).discover(mcp, scope: scope)
    else { throw ConnectError.server("no sign-in") }
    return discovery
  }

  @Test func theResourceMetadataNamedInTheChallengeIsReadFirst() async throws {
    let web = FakeWeb()
    Servers.notionLike(web)

    let discovery = try await discover(web)

    #expect(discovery.resource.resource == "https://mcp.example.com/mcp")
    #expect(discovery.server.tokenEndpoint.absoluteString == "https://mcp.example.com/token")
    #expect(web.requests[1].url.absoluteString == "https://mcp.example.com/.well-known/oauth-protected-resource/mcp")
  }

  @Test func theScopeInTheChallengeWinsOverScopesSupportedAndTheCatalogOverBoth() async throws {
    let web = FakeWeb()
    Servers.notionLike(web)
    #expect(try await discover(web).resource.scope == "read")
    #expect(try await discover(web, scope: "read:issues").resource.scope == "read:issues")

    let quiet = FakeWeb()
    Servers.notionLike(quiet, challenge: false)
    #expect(try await discover(quiet).resource.scope == "read write")
  }

  @Test func anAuthorizationServerOnAnotherHostWithAPathIsFoundByPathInsertion() async throws {
    let web = FakeWeb()
    let mcp = try #require(URL(string: "https://mcp.shop.example/"))
    web.json("POST", mcp.absoluteString, "{}", status: 401, headers: ["WWW-Authenticate": "Bearer"])
    web.json(
      "GET", "https://mcp.shop.example/.well-known/oauth-protected-resource",
      #"{ "resource": "https://mcp.shop.example", "authorization_servers": ["https://access.shop.example/mcp"] }"#)
    web.json(
      "GET", "https://access.shop.example/.well-known/oauth-authorization-server/mcp",
      Servers.metadata.replacing("https://mcp.example.com", with: "https://access.shop.example/mcp"))

    let discovery = try await discover(web, mcp)

    #expect(discovery.server.issuer.absoluteString == "https://access.shop.example/mcp")
    #expect(discovery.server.authorizationEndpoint.absoluteString == "https://access.shop.example/mcp/authorize")
  }

  @Test func withoutResourceMetadataTheMcpHostIsTheAuthorizationServer() async throws {
    let web = FakeWeb()
    let mcp = try #require(URL(string: "https://mcp.wiki.example/v1/mcp"))
    web.json("POST", mcp.absoluteString, "{}", status: 401)
    web.json("GET", "https://mcp.wiki.example/.well-known/oauth-authorization-server", Servers.metadata)

    let discovery = try await discover(web, mcp)

    #expect(discovery.resource.issuer.absoluteString == "https://mcp.wiki.example")
    #expect(discovery.resource.resource == mcp.absoluteString)
  }

  @Test func aServerThatDoesNotOfferS256IsRefused() async {
    let web = FakeWeb()
    Servers.notionLike(web)
    web.json(
      "GET", "https://mcp.example.com/.well-known/oauth-authorization-server",
      Servers.metadata.replacing(#"["S256"]"#, with: #"["plain"]"#))

    await #expect(throws: ConnectError.unsupported("the authorization server does not offer PKCE with S256")) {
      try await discover(web)
    }
  }

  @Test func aServerWithoutRegistrationSaysItNeedsAnAppRegisteredAhead() async {
    let web = FakeWeb()
    Servers.notionLike(web)
    web.json(
      "GET", "https://mcp.example.com/.well-known/oauth-authorization-server",
      Servers.metadata.replacing(#""registration_endpoint": "https://mcp.example.com/register","#, with: ""))

    await #expect(
      throws: ConnectError.unsupported(
        "this server needs an app registered with it ahead; Loci cannot connect to it yet")
    ) { try await discover(web) }
  }

  @Test func aServerThatAnswersWithoutASignInAndNamesNoneIsOpen() async throws {
    let web = FakeWeb()
    web.json("POST", Servers.mcp.absoluteString, "{}")

    #expect(try await OAuth(http: web, randomBytes: Servers.bytes).discover(Servers.mcp) == .open)
  }
}
