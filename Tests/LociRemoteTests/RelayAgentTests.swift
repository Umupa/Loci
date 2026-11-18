import Foundation
import Testing

@testable import LociRemote

/// The agent and client ends of alma-relay's protocol, against the in-process relay.
struct RelayAgentTests {
  static let token = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  static let quick = Heartbeat(interval: .milliseconds(20), missesAllowed: 2, dialTimeout: .milliseconds(200))
  static let soon = Backoff(first: .milliseconds(5), longest: .milliseconds(20))

  static func agent(on relay: LoopbackRelay, token: String = token, key: String? = nil) async -> RelayAgent {
    RelayAgent(
      relay: Relay(address: LoopbackRelay.address, registrationKey: key), token: token, dialer: relay,
      heartbeat: quick, backoff: soon)
  }

  @Test func theAgentRegistersItsTokenHashWithTheNewestProtocol() async throws {
    let relay = LoopbackRelay()
    var events = await Self.agent(on: relay).run().makeAsyncIterator()

    guard case .registered(let proto) = await events.next() else { throw Unexpected() }

    #expect(proto == 3)
    #expect(await relay.registeredCount == 1)
  }

  @Test func theAgentFallsBackToAnOlderRelaysProtocol() async throws {
    let relay = LoopbackRelay(proto: 2)
    var events = await Self.agent(on: relay).run().makeAsyncIterator()

    guard case .registered(let proto) = await events.next() else { throw Unexpected() }

    #expect(proto == 2)
  }

  @Test func theAgentStopsWhenAnotherRegistersTheSameToken() async throws {
    let relay = LoopbackRelay()
    var first = await Self.agent(on: relay).run().makeAsyncIterator()
    guard case .registered = await first.next() else { throw Unexpected() }
    var second = await Self.agent(on: relay).run().makeAsyncIterator()
    guard case .registered = await second.next() else { throw Unexpected() }

    guard case .stopped(let reason) = await first.next() else { throw Unexpected() }

    #expect(reason == .displaced)
    #expect(await first.next() == nil)
  }

  @Test func theAgentStopsWhenTheRelayRefusesItsKey() async throws {
    let relay = LoopbackRelay(registrationKey: "right")
    var events = await Self.agent(on: relay, key: "wrong").run().makeAsyncIterator()

    guard case .stopped(let reason) = await events.next() else { throw Unexpected() }

    #expect(reason == .keyRejected)
  }

  @Test func onlyTheLociPathIsServed() async throws {
    let relay = LoopbackRelay()
    var events = await Self.agent(on: relay).run().makeAsyncIterator()
    guard case .registered = await events.next() else { throw Unexpected() }

    let elsewhere = try await relay.dial(URL(string: "ws://loopback.relay/c/\(Self.token)/__alma_e2e__")!)
    await #expect(throws: SocketError.closed(code: 1011)) { try await elsewhere.receive() }

    let client = try await RelayClient.open(relay.relay, token: Self.token, dialer: relay, heartbeat: Self.quick)
    guard case .connection(let served) = await events.next() else { throw Unexpected() }
    try await client.send(.binary(Data("hello".utf8)))
    #expect(try await served.receive() == .binary(Data("hello".utf8)))
    try await served.send(.binary(Data("back".utf8)))
    #expect(try await client.receive() == .binary(Data("back".utf8)))
  }

  @Test func aMacNotOnTheRelayCannotBeOpened() async throws {
    let relay = LoopbackRelay()

    await #expect(throws: SocketError.notOnRelay) {
      _ = try await RelayClient.open(relay.relay, token: Self.token, dialer: relay, heartbeat: Self.quick)
    }
  }

  @Test func aClientThatStopsReadingHoldsUpOnlyItsOwnSocket() async throws {
    let relay = LoopbackRelay(window: 1 << 16)
    var events = await Self.agent(on: relay).run().makeAsyncIterator()
    guard case .registered = await events.next() else { throw Unexpected() }
    let stalled = try await RelayClient.open(relay.relay, token: Self.token, dialer: relay, heartbeat: Self.quick)
    guard case .connection(let toStalled) = await events.next() else { throw Unexpected() }
    let reading = try await RelayClient.open(relay.relay, token: Self.token, dialer: relay, heartbeat: Self.quick)
    guard case .connection(let toReading) = await events.next() else { throw Unexpected() }
    let sent = Counter()

    let flooding = Task {
      for _ in 0..<64 {
        try await toStalled.send(.binary(Data(count: 1 << 14)))
        await sent.add()
      }
    }
    for index in 0..<20 {
      try await toReading.send(.text("message \(index)"))
      #expect(try await reading.receive() == .text("message \(index)"))
    }

    #expect(await sent.value <= 5)
    for _ in 0..<64 { _ = try await stalled.receive() }
    try await flooding.value
    #expect(await sent.value == 64)
  }

  @Test func theAgentRegistersAgainAfterTheRelayGoesSilent() async throws {
    let relay = LoopbackRelay()
    var events = await Self.agent(on: relay).run().makeAsyncIterator()
    guard case .registered = await events.next() else { throw Unexpected() }

    await relay.fallSilent()
    guard case .disconnected(let reason) = await events.next() else { throw Unexpected() }
    await relay.restart()

    #expect(reason == .timedOut)
    guard case .registered = await events.next() else { throw Unexpected() }
  }

  @Test func aDialThatTakesTooLongFails() async throws {
    await #expect(throws: SocketError.timedOut) {
      _ = try await RelayClient.open(
        Relay(address: LoopbackRelay.address, registrationKey: nil), token: Self.token, dialer: NeverAnswers(),
        heartbeat: Self.quick)
    }
  }
}

struct Unexpected: Error {}

actor Counter {
  private(set) var value = 0
  func add() { value += 1 }
}

struct NeverAnswers: SocketDialer {
  func dial(_ url: URL) async throws(SocketError) -> any WebSocket {
    try? await Task.sleep(for: .seconds(3600))
    throw .timedOut
  }
}
