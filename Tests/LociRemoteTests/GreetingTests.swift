import Foundation
import LociModel
import Testing

@testable import LociRemote

/// Two Macs greet each other through the in-process relay.
struct GreetingTests {
  struct Mac {
    let key: DeviceKey
    let machine: Machine

    init(_ name: String) throws {
      key = try DeviceKey()
      machine = Machine(id: key.machineID, name: name, model: .mini)
    }
  }

  /// The agent keeps running for as long as the returned events are held.
  static func connect(_ relay: LoopbackRelay, to mac: Mac) async throws -> (
    client: any MessageSocket, served: any MessageSocket, agent: AsyncStream<AgentEvent>
  ) {
    let events = RelayAgent(relay: relay.relay, token: mac.key.routeToken, dialer: relay).run()
    var iterator = events.makeAsyncIterator()
    guard case .registered = await iterator.next() else { throw Unexpected() }
    let client = try await RelayClient.open(relay.relay, token: mac.key.routeToken, dialer: relay)
    guard case .connection(let served) = await iterator.next() else { throw Unexpected() }
    return (client, served, events)
  }

  @Test func pairedMacsGreetAndTalkInBothDirections() async throws {
    let relay = LoopbackRelay()
    let studio = try Mac("Mac Studio")
    let laptop = try Mac("MacBook")
    let (client, served, agent) = try await Self.connect(relay, to: studio)
    defer { withExtendedLifetime(agent) {} }

    async let answered = Greeting.answer(served, as: studio.key) { hello in
      #expect(hello.from == laptop.machine)
      return .welcome(studio.machine, preSharedKey: nil)
    }
    let dialed = try await Greeting.dial(
      client, as: laptop.key, me: laptop.machine, to: studio.key.address, purpose: .open(.control))
    let greeted = try #require(try await answered)

    #expect(dialed.peer == studio.machine)
    #expect(greeted.peer == laptop.machine)
    #expect(greeted.purpose == .open(.control))
    #expect(dialed.code == greeted.code)
    let large = Data((0..<200_000).map { UInt8($0 % 251) })
    try await dialed.channel.send(large)
    #expect(try await greeted.channel.receive() == large)
    try await greeted.channel.send(Data("back".utf8))
    #expect(try await dialed.channel.receive() == Data("back".utf8))
  }

  @Test func aRefusalOfAnUnknownKeyIsAuthenticated() async throws {
    let relay = LoopbackRelay()
    let studio = try Mac("Mac Studio")
    let stranger = try Mac("Stranger")
    let (client, served, agent) = try await Self.connect(relay, to: studio)
    defer { withExtendedLifetime(agent) {} }

    async let answered = Greeting.answer(served, as: studio.key) { _ in .refuse(.unknown) }

    await #expect(throws: GreetingError.refused(.unknown)) {
      _ = try await Greeting.dial(
        client, as: stranger.key, me: stranger.machine, to: studio.key.address, purpose: .open(.control))
    }
    #expect(try await answered == nil)
  }

  @Test func anInvitesSecretMustMatch() async throws {
    let relay = LoopbackRelay()
    let studio = try Mac("Mac Studio")
    let laptop = try Mac("MacBook")
    let (client, served, agent) = try await Self.connect(relay, to: studio)
    defer { withExtendedLifetime(agent) {} }

    async let answered = Greeting.answer(served, as: studio.key) { _ in
      .welcome(studio.machine, preSharedKey: Data(repeating: 2, count: 32))
    }

    await #expect(throws: GreetingError.channel(.noise(.decryptFailed))) {
      _ = try await Greeting.dial(
        client, as: laptop.key, me: laptop.machine, to: studio.key.address, purpose: .invite(EntityID()),
        preSharedKey: Data(repeating: 1, count: 32))
    }
    _ = try? await answered
  }

  @Test func aSpentInviteIsRefusedInTheClear() async throws {
    let relay = LoopbackRelay()
    let studio = try Mac("Mac Studio")
    let laptop = try Mac("MacBook")
    let (client, served, agent) = try await Self.connect(relay, to: studio)
    defer { withExtendedLifetime(agent) {} }

    async let answered = Greeting.answer(served, as: studio.key) { _ in .refuse(.inviteUsed) }

    await #expect(throws: GreetingError.refused(.inviteUsed)) {
      _ = try await Greeting.dial(
        client, as: laptop.key, me: laptop.machine, to: studio.key.address, purpose: .invite(EntityID()),
        preSharedKey: Data(repeating: 1, count: 32))
    }
    #expect(try await answered == nil)
  }

  @Test func aMacAnsweringWithAnotherKeyIsNotTrusted() async throws {
    let relay = LoopbackRelay()
    let studio = try Mac("Mac Studio")
    let impostor = try Mac("Mac Studio")
    let laptop = try Mac("MacBook")
    let (client, served, agent) = try await Self.connect(relay, to: impostor)
    defer { withExtendedLifetime(agent) {} }

    async let answered = Greeting.answer(served, as: impostor.key) { _ in .welcome(impostor.machine, preSharedKey: nil)
    }

    await #expect(throws: GreetingError.self) {
      _ = try await Greeting.dial(
        client, as: laptop.key, me: laptop.machine, to: studio.key.address, purpose: .pair)
    }
    _ = try? await answered
  }

  @Test func theRelaySeesNoPlainText() async throws {
    let relay = LoopbackRelay()
    let studio = try Mac("Mac Studio")
    let laptop = try Mac("MacBook")
    let (client, served, agent) = try await Self.connect(relay, to: studio)
    defer { withExtendedLifetime(agent) {} }
    async let answered = Greeting.answer(served, as: studio.key) { _ in .welcome(studio.machine, preSharedKey: nil) }
    let dialed = try await Greeting.dial(
      client, as: laptop.key, me: laptop.machine, to: studio.key.address, purpose: .open(.control))
    let greeted = try #require(try await answered)

    try await dialed.channel.send(Data("调度器的公平性".utf8))
    _ = try await greeted.channel.receive()

    let seen = await relay.traffic.reduce(Data(), +)
    #expect(seen.range(of: Data("调度器".utf8)) == nil)
    #expect(seen.range(of: Data("MacBook".utf8)) == nil)
  }
}

struct DeviceKeyTests {
  @Test func theRouteTokenIsStableForAKeyAndDiffersBetweenKeys() throws {
    let key = try DeviceKey()
    let again = try DeviceKey(rawRepresentation: key.rawRepresentation)

    #expect(again.routeToken == key.routeToken)
    #expect(try DeviceKey().routeToken != key.routeToken)
    #expect(key.routeToken.count == 43)
  }
}
