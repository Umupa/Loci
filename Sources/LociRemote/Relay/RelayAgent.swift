import Foundation
import os

/// This Mac's registration with the relay. It serves only `/__loci__`, answers every plain HTTP request
/// with 403, and keeps each bridged socket within the relay's per-stream window (protocol 3), so a client
/// that reads slowly holds back only its own socket.
public actor RelayAgent {
  private let relay: Relay
  private let tokenHash: String
  private let dialer: any SocketDialer
  private let heartbeat: Heartbeat
  private let backoff: Backoff
  private let clock: any Clock<Duration>
  private let random: @Sendable () -> Double

  private var socket: (any MessageSocket)?
  private var proto = 1
  private var window = Int.max
  private var streams: [String: BridgedSocket] = [:]
  private var unacknowledged: [String: Int] = [:]
  private var waitingForCredit: [String: [CheckedContinuation<Void, Never>]] = [:]

  private static let log = Logger(subsystem: "com.loci.native.dev", category: "relay")

  public init(
    relay: Relay, token: String, dialer: any SocketDialer, heartbeat: Heartbeat = Heartbeat(),
    backoff: Backoff = Backoff(), clock: any Clock<Duration> = ContinuousClock(),
    random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
  ) {
    self.relay = relay
    tokenHash = Relay.tokenHash(of: token)
    self.dialer = dialer
    self.heartbeat = heartbeat
    self.backoff = backoff
    self.clock = clock
    self.random = random
  }

  /// Registers, and keeps registering again after each loss, until the stream is dropped or the relay
  /// says to stop.
  public nonisolated func run() -> AsyncStream<AgentEvent> {
    let (events, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
    let running = Task { await self.keepRegistered(continuation) }
    continuation.onTermination = { _ in running.cancel() }
    return events
  }

  private func keepRegistered(_ events: AsyncStream<AgentEvent>.Continuation) async {
    var attempt = 0
    while !Task.isCancelled {
      do throws(AgentFailure) {
        let socket = try await register()
        attempt = 0
        events.yield(.registered(proto: proto))
        throw await withTaskCancellationHandler {
          await serve(socket, events: events)
        } onCancel: {
          Task { await socket.close(code: 1000) }
        }
      } catch {
        await lose()
        switch error {
        case .stop(let reason):
          events.yield(.stopped(reason))
          events.finish()
          return
        case .lost(let reason):
          guard !Task.isCancelled else { break }
          events.yield(.disconnected(reason))
        }
      }
      guard (try? await clock.sleep(for: backoff.delay(attempt: attempt, random: random()))) != nil else { break }
      attempt += 1
    }
    await lose()
    events.finish()
  }

  private func register() async throws(AgentFailure) -> any MessageSocket {
    let url = relay.agentURL(tokenHash: tokenHash)
    let dialer = dialer
    let kept: KeptAlive
    do throws(SocketError) {
      let raw = try await within(heartbeat.dialTimeout, on: clock) { () async throws(SocketError) in
        try await dialer.dial(url)
      }
      kept = KeptAlive(raw, heartbeat: heartbeat, clock: clock)
      await kept.start()
      let frame = AgentFrame.register(tokenHash: tokenHash, key: relay.registrationKey, proto: Relay.newestProtocol)
      try await kept.send(frame.encoded(proto: 1))
      while true {
        switch AgentFrame(try await kept.receive()) {
        case .registered(let proto, let window):
          self.proto = proto
          self.window = proto >= 3 ? max(window ?? 1 << 20, 1 << 16) : .max
          socket = kept
          return kept
        case .error(let message):
          Self.log.error("relay refused the registration: \(message, privacy: .public)")
        default:
          continue
        }
      }
    } catch {
      throw AgentFailure(error)
    }
  }

  /// Serves until the relay connection is lost, and says how.
  private func serve(_ socket: any MessageSocket, events: AsyncStream<AgentEvent>.Continuation) async -> AgentFailure {
    while true {
      let message: SocketMessage
      do {
        message = try await socket.receive()
      } catch {
        return AgentFailure(error)
      }
      guard let frame = AgentFrame(message) else { continue }
      switch frame {
      case .httpRequest(let id):
        try? await socket.send(AgentFrame.httpResponse(id: id, status: 403).encoded(proto: proto))
        try? await socket.send(AgentFrame.httpEnd(id: id).encoded(proto: proto))
      case .socketOpen(let id, let path):
        guard path == Relay.lociPath else {
          try? await socket.send(AgentFrame.socketError(id: id, message: "not served").encoded(proto: proto))
          continue
        }
        let bridged = BridgedSocket(id: id, agent: self)
        streams[id] = bridged
        try? await socket.send(AgentFrame.socketOpened(id: id).encoded(proto: proto))
        events.yield(.connection(bridged))
      case .socketMessage(let id, let message):
        await streams[id]?.deliver(message)
      case .socketClose(let id, let code):
        await end(id, code: code ?? 1000)
      case .ack(let id, let bytes):
        unacknowledged[id] = max(0, (unacknowledged[id] ?? 0) - bytes)
        resumeWaiting(id)
      case .register, .registered, .error, .httpResponse, .httpEnd, .socketOpened, .socketError, .ignored:
        continue
      }
    }
  }

  func send(_ message: SocketMessage, on id: String) async throws(SocketError) {
    while streams[id] != nil, (unacknowledged[id] ?? 0) >= window {
      await withCheckedContinuation { waitingForCredit[id, default: []].append($0) }
    }
    guard streams[id] != nil, let socket else { throw .closed(code: 1006) }
    unacknowledged[id, default: 0] += message.byteCount
    try await socket.send(AgentFrame.socketMessage(id: id, message).encoded(proto: proto))
  }

  func close(_ id: String, code: Int) async {
    guard streams[id] != nil else { return }
    try? await socket?.send(AgentFrame.socketClose(id: id, code: code).encoded(proto: proto))
    await end(id, code: code)
  }

  private func end(_ id: String, code: Int) async {
    let stream = streams.removeValue(forKey: id)
    unacknowledged[id] = nil
    resumeWaiting(id)
    await stream?.finish(code: code)
  }

  private func resumeWaiting(_ id: String) {
    for waiter in waitingForCredit.removeValue(forKey: id) ?? [] { waiter.resume() }
  }

  /// The relay closes every bridged socket when the agent socket goes, so they all end here too.
  private func lose() async {
    let ending = streams.keys
    for id in ending { await end(id, code: 1012) }
    await socket?.close(code: 1000)
    socket = nil
  }
}

enum AgentFailure: Error {
  case stop(AgentStop)
  case lost(SocketError)

  init(_ error: SocketError) {
    switch error {
    case .closed(4000): self = .stop(.displaced)
    case .closed(4002): self = .stop(.badTokenHash)
    case .closed(4003), .closed(4401): self = .stop(.keyRejected)
    default: self = .lost(error)
    }
  }
}

extension SocketMessage {
  /// What the relay counts against a stream's window: the payload bytes.
  var byteCount: Int {
    switch self {
    case .text(let text): text.utf8.count
    case .binary(let data): data.count
    }
  }
}
