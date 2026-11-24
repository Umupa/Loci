import Foundation
import LociConnect
import LociModel
import LociStore
import Testing

@testable import LociHost

/// CN-S2, CN-S11, CN-S12: websites signed into in the built-in browser are connectors the companion reads
/// with that sign-in, sending only GET, never from a cache.
@Suite(.timeLimit(.minutes(1)))
struct WebsiteConnectorScenarioTests {
  static let x = ConnectorID("x")

  private func connected(_ host: LocalHost, where match: @escaping @Sendable (Connectors) -> Bool) async -> Connectors?
  {
    await value(host.subscribe(WatchConnectors()), where: match)
  }

  @Test func everyWebsiteIsSignedIntoOnTheDomainsItsIconIsKnownBy() throws {
    for entry in ConnectorCatalog.sites {
      let domains = try #require(entry.site?.domains)
      #expect(!domains.isEmpty && domains.allSatisfy { ConnectorSites.connector(for: $0) == entry.offer.id })
    }
  }

  @Test func aSiteSignedIntoInTheBuiltInBrowserIsConnectedOnItsOwn() async throws {
    let world = ConnectWorld()
    world.sites.signIn("x.com", cookie: "auth_token")
    try await withHost(connect: world.environment) { host, _, _ in
      let page = try #require(await connected(host) { $0.connected.contains { $0.id == Self.x } })
      let x = try #require(page.connected.first { $0.id == Self.x })
      #expect(x.source == .site && x.account == nil && x.server.absoluteString == "https://x.com")
      #expect(x.tools.map(\.name) == ["read"])
      #expect(!page.available.contains { $0.id == Self.x })
      #expect(
        page.available.map(\.id.rawValue).suffix(5) == ["v2ex", "xiaohongshu", "bilibili", "calendar", "reminders"])
    }
  }

  @Test func connectingOpensTheSignInPageInTheBuiltInBrowserAndASignInFinishesIt() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let authorization = try await host.run(Connect(ConnectorID("v2ex")))
      #expect(authorization == .openInBuiltInBrowser(URL(string: "https://www.v2ex.com/signin")!))
      #expect(try await host.connectors().attempts[ConnectorID("v2ex")] != nil)

      world.sites.signIn("v2ex.com", cookie: "A2")

      let page = try #require(
        await connected(host) { $0.connected.contains { $0.id == ConnectorID("v2ex") } && $0.attempts.isEmpty })
      #expect(page.connected.first?.status == .ready)
    }
  }

  @Test func signingOutAsksForReconnectingAndSigningInAgainMendsIt() async throws {
    let world = ConnectWorld()
    world.sites.signIn("bilibili.com", cookie: "SESSDATA")
    try await withHost(connect: world.environment) { host, _, _ in
      _ = await connected(host) { $0.connected.contains { $0.status == .ready } }

      world.sites.signOut("bilibili.com")
      let out = try #require(
        await connected(host) { $0.connected.first.map { $0.status != .ready } ?? false })
      #expect(out.connected.first?.status == .needsReconnecting("signed out of 哔哩哔哩 in the built-in browser"))

      world.sites.signIn("bilibili.com", cookie: "SESSDATA")
      #expect(await connected(host) { $0.connected.first?.status == .ready } != nil)
    }
  }

  @Test func anExpiredSignInIsNotASignIn() async throws {
    let world = ConnectWorld()
    world.sites.signIn("x.com", cookie: "auth_token", expires: Date(timeIntervalSince1970: 0))
    world.sites.signIn("x.com", cookie: "guest_id")
    try await withHost(connect: world.environment) { host, _, _ in
      try await Task.sleep(for: .milliseconds(100))
      #expect(try await host.connectors().connected.isEmpty)
    }
  }

  @Test func disconnectingStopsUsingTheSignInWithoutSigningOutAndItIsNotAddedBack() async throws {
    let world = ConnectWorld()
    world.sites.signIn("x.com", cookie: "auth_token")
    try await withHost(connect: world.environment) { host, _, _ in
      _ = await connected(host) { !$0.connected.isEmpty }

      _ = try await host.run(Disconnect(Self.x))
      world.sites.signIn("x.com", cookie: "ct0")
      try await Task.sleep(for: .milliseconds(100))

      let page = try await host.connectors()
      #expect(page.connected.isEmpty && page.available.contains { $0.id == Self.x })
      #expect(await world.sites.cookies(on: ["x.com"]).contains { $0.name == "auth_token" })

      #expect(try await host.run(Connect(Self.x)) == .connected)
      #expect(try await host.connectors().connected.map(\.id) == [Self.x])
    }
  }

  @Test func lociReadOnAConnectedSiteReadsSignedInFreshAndMarkedAsOutside() async throws {
    let world = ConnectWorld()
    world.sites.signIn("x.com", cookie: "auth_token")
    try await withHost(connect: world.environment) { host, _, _ in
      _ = await connected(host) { !$0.connected.isEmpty }
      let page = URL(string: "https://x.com/TencentCloud/status/1")!

      for _ in 0..<2 {
        let reply = await Background.call(ReadSource(url: page), from: .conversation(.main), on: host)
        guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
        let text = try JSONDecoder().decode(String.self, from: data)
        #expect(text.contains("<external-content connector=\"x\" tool=\"read\">") && text.contains("v0.9 发布"))
      }

      #expect(world.sites.read == [page, page])
      let calls = try await host.connectorCalls(limit: 10)
      #expect(calls.map(\.tool) == ["read", "read"] && calls.allSatisfy { $0.outcome == .read })
    }
  }

  @Test func theReadToolTakesOnlyPagesOfItsOwnSite() async throws {
    let world = ConnectWorld()
    world.sites.signIn("x.com", cookie: "auth_token")
    try await withHost(connect: world.environment) { host, _, _ in
      _ = await connected(host) { !$0.connected.isEmpty }

      let own = await Background.call(
        CallConnector(Self.x, tool: "read", arguments: #"{"url": "https://twitter.com/x/status/2"}"#),
        from: .run(EntityID()), on: host)
      let other = await Background.call(
        CallConnector(Self.x, tool: "read", arguments: #"{"url": "https://evil.example/steal"}"#),
        from: .conversation(.main), on: host)

      guard case .value = own else { throw HostError.invalidRequest("\(String(describing: own))") }
      guard case .failed(.invalidRequest(let why))? = other else { throw HostError.invalidRequest("read another site") }
      #expect(why.contains("is not a page of X"))
      #expect(world.sites.read == [URL(string: "https://twitter.com/x/status/2")!])
    }
  }
}
