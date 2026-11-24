import Foundation
import LociConnect
import LociModel
import LociStore
import Testing

@testable import LociHost

/// CN-S1, CN-S2, CN-S8: connecting in the browser, disconnecting, and only on the Mac the companion lives on.
@Suite(.timeLimit(.minutes(1)))
struct ConnectorScenarioTests {
  static let notion = ConnectorID("notion")

  @Test func connectingGivesTheBrowserPageAndTheCallbackMakesItConnected() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let before = try await host.connectors()
      #expect(
        before.available.map(\.id.rawValue) == [
          "notion", "linear", "github", "sentry", "atlassian", "x", "v2ex", "xiaohongshu", "bilibili", "calendar",
          "reminders",
        ])

      let authorization = try await host.run(Connect(Self.notion))
      guard case .open(let page) = authorization else { throw HostError.invalidRequest("no page") }
      #expect(page.absoluteString.hasPrefix("https://mcp.notion.com/authorize?"))
      #expect(
        try await host.connectors().attempts[Self.notion].map { if case .waiting = $0 { true } else { false } } == true)
      try await world.browser.signIn(at: authorization)

      let connected = try #require(
        await value(host.subscribe(WatchConnectors())) { !$0.connected.isEmpty && $0.attempts.isEmpty })
      let notion = try #require(connected.connected.first)
      #expect(notion.name == "Notion" && notion.account == "Umi 的空间" && notion.status == .ready)
      #expect(notion.tools.map(\.name) == ["search"])
      #expect(!connected.available.contains { $0.id == Self.notion })
      #expect(world.vault.all[Self.notion] != nil)
    }
  }

  @Test func eachConnectionRegistersAgainAtTheNewPort() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      try await world.connectNotion(on: host)

      try await world.connectNotion(on: host)

      #expect(world.services.registered == ["http://127.0.0.1:53001/callback", "http://127.0.0.1:53002/callback"])
    }
  }

  @Test func aSignInTheBrowserNeverFinishesIsGivenUp() async throws {
    var world = ConnectWorld()
    world.patience = .milliseconds(100)
    try await withHost(connect: world.environment) { host, _, _ in
      _ = try await host.run(Connect(Self.notion))

      let given = await value(host.subscribe(WatchConnectors())) { connectors in
        if case .failed = connectors.attempts[Self.notion] { true } else { false }
      }

      #expect(given?.connected.isEmpty == true)
      #expect(world.vault.all.isEmpty)
    }
  }

  @Test func aSignInTheyRefusedSaysWhy() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let authorization = try await host.run(Connect(Self.notion))

      try await world.browser.signIn(at: authorization, query: "error=access_denied")

      let refused = await value(host.subscribe(WatchConnectors())) { connectors in
        if case .failed = connectors.attempts[Self.notion] { true } else { false }
      }
      #expect(refused?.attempts[Self.notion] == .failed("access_denied"))
    }
  }

  @Test func disconnectingDeletesTheCredentialAndTheCompanionNoLongerSeesIt() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      try await world.connectNotion(on: host)

      _ = try await host.run(Disconnect(Self.notion))

      #expect(world.vault.all.isEmpty)
      #expect(try await host.connectors().connected.isEmpty)
      let reply = await Background.call(ListConnectors(), from: .conversation(.main), on: host)
      #expect(reply == .value(try JSONEncoder().encode([Connector]())))
    }
  }

  @Test func githubIsConnectedWithTheSignedInGhAndItsReadOnlyAddress() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let authorization = try await host.run(Connect(ConnectorID("github")))

      let github = try #require(try await host.connectors().connected.first)
      #expect(authorization == .connected)
      #expect(github.server.absoluteString == FakeServices.github && github.account == "umupa")
      #expect(world.services.bearers.allSatisfy { $0 == "gh-token" } && !world.services.bearers.isEmpty)
      #expect(world.vault.all.isEmpty)
    }
  }

  @Test func githubWithoutASignedInGhSaysWhatToDo() async throws {
    var world = ConnectWorld()
    world.signedInGh = false
    try await withHost(connect: world.environment) { host, _, _ in
      await #expect(
        throws: HostError.invalidRequest("gh is not signed in on this Mac; run `gh auth login` in Terminal first")
      ) {
        _ = try await host.run(Connect(ConnectorID("github")))
      }
    }
  }

  @Test func anAddedAddressConnectsTheSameWayUnderItsHost() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let authorization = try await host.run(AddMCPServer(try #require(URL(string: FakeServices.notion))))
      try await world.browser.signIn(at: authorization)

      let connected = await value(host.subscribe(WatchConnectors())) { !$0.connected.isEmpty }

      #expect(connected?.connected.map(\.id.rawValue) == ["mcp-mcp.notion.com"])
      #expect(connected?.connected.first?.name == "mcp.notion.com")
    }
  }

  @Test func anAddressThatCannotBeSignedInWithSaysSo() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let unknown = try #require(URL(string: "https://mcp.elsewhere.example/mcp"))

      await #expect(throws: HostError.self) { _ = try await host.run(AddMCPServer(unknown)) }
      #expect(try await host.connectors().connected.isEmpty)
    }
  }

  @Test func anotherMacSeesTheConnectorsAndDisconnectsButCannotStartAConnection() async throws {
    let place = Place()
    defer { place.remove() }
    let remote = RemoteHost(
      machine: MachineID(publicKey: Data([1, 2, 3])),
      folder: MachineFolder(root: place.root), link: { nil }, keep: { _, _, _ in })

    await #expect(
      throws: HostError.invalidRequest("\(Connect.name) can only be done on the Mac the companion lives on")
    ) {
      _ = try await remote.run(Connect(Self.notion))
    }
    await #expect(throws: HostError.offline) { _ = try await remote.run(Disconnect(Self.notion)) }
    #expect(Wire.subscriptions.contains { $0 == WatchConnectors.self })
    #expect(Wire.subscriptions.contains { $0 == WatchConnectorCalls.self })
  }
}
