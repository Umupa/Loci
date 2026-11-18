/// How often to ping the relay, and how long silence may last before the connection counts as dead.
public struct Heartbeat: Sendable {
  public let interval: Duration
  /// Silence for this many intervals in a row means dead. Any message or pong counts as being heard.
  public let missesAllowed: Int
  /// How long a dial may take before it is given up.
  public let dialTimeout: Duration

  public init(interval: Duration = .seconds(15), missesAllowed: Int = 3, dialTimeout: Duration = .seconds(15)) {
    self.interval = interval
    self.missesAllowed = missesAllowed
    self.dialTimeout = dialTimeout
  }
}

/// A WebSocket that notices when the far end goes silent. It pings every interval; when nothing has been
/// heard for `missesAllowed` intervals it closes the socket, and `receive` throws `timedOut`.
actor KeptAlive: MessageSocket {
  private let socket: any WebSocket
  private let heartbeat: Heartbeat
  private let clock: any Clock<Duration>
  private var heard = true
  private var silentBeats = 0
  private var isDead = false
  private var beating: Task<Void, Never>?

  init(_ socket: any WebSocket, heartbeat: Heartbeat, clock: any Clock<Duration>) {
    self.socket = socket
    self.heartbeat = heartbeat
    self.clock = clock
  }

  func start() {
    beating = Task { [weak self] in await self?.beat() }
  }

  func send(_ message: SocketMessage) async throws(SocketError) {
    guard !isDead else { throw .timedOut }
    try await socket.send(message)
  }

  func receive() async throws(SocketError) -> SocketMessage {
    do {
      let message = try await socket.receive()
      heard = true
      return message
    } catch {
      throw isDead ? .timedOut : error
    }
  }

  func close(code: Int) async {
    beating?.cancel()
    await socket.close(code: code)
  }

  private func beat() async {
    while !Task.isCancelled {
      do {
        try await clock.sleep(for: heartbeat.interval)
      } catch {
        return
      }
      silentBeats = heard ? 0 : silentBeats + 1
      heard = false
      if silentBeats >= heartbeat.missesAllowed {
        isDead = true
        await socket.close(code: 1001)
        return
      }
      let socket = socket
      Task { [weak self] in
        guard (try? await socket.ping()) != nil else { return }
        await self?.markHeard()
      }
    }
  }

  private func markHeard() {
    heard = true
  }
}

/// Runs `work`, giving up with `timedOut` when it takes longer than `limit`.
func within<Value: Sendable>(
  _ limit: Duration, on clock: any Clock<Duration>,
  _ work: @escaping @Sendable () async throws(SocketError) -> Value
) async throws(SocketError) -> Value {
  let outcome = await withTaskGroup(of: Result<Value, SocketError>?.self) { group in
    group.addTask {
      do throws(SocketError) {
        return .success(try await work())
      } catch {
        return .failure(error)
      }
    }
    group.addTask {
      guard (try? await clock.sleep(for: limit)) != nil else { return nil }
      return .failure(.timedOut)
    }
    let first = await group.next() ?? nil
    group.cancelAll()
    return first ?? .failure(.timedOut)
  }
  return try outcome.get()
}
