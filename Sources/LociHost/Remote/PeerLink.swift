import Foundation
import LociModel
import LociRemote
import LociStore

/// Reaching the relay: where it is, how to dial it, and how patient to be.
public struct RelayAccess: Sendable {
  public let relay: Relay
  let dialer: any SocketDialer
  let heartbeat: Heartbeat
  let backoff: Backoff
  let clock: any Clock<Duration>
  let random: @Sendable () -> Double
  /// How long the data connection stays open with no request started and none in flight.
  let dataIdle: Duration

  public init(
    relay: Relay, dialer: any SocketDialer, heartbeat: Heartbeat = Heartbeat(), backoff: Backoff = Backoff(),
    clock: any Clock<Duration> = ContinuousClock(), random: @escaping @Sendable () -> Double = { .random(in: 0..<1) },
    dataIdle: Duration = .seconds(60)
  ) {
    self.dataIdle = dataIdle
    self.relay = relay
    self.dialer = dialer
    self.heartbeat = heartbeat
    self.backoff = backoff
    self.clock = clock
    self.random = random
  }

  func open(_ address: PeerAddress) async throws(SocketError) -> any MessageSocket {
    try await RelayClient.open(relay, token: address.routeToken, dialer: dialer, heartbeat: heartbeat, clock: clock)
  }

  func pause(attempt: Int) async -> Bool {
    (try? await clock.sleep(for: backoff.delay(attempt: attempt, random: random()))) != nil
  }
}

/// What a link reports about its Mac.
enum PeerEvent: Sendable {
  case link(Link)
  /// The Mac answered that this one is not in its roster.
  case refused
  /// The Mac said it removed this one.
  case unpaired
}

/// The connections to one paired Mac. The control connection is kept up for as long as the Mac is in the
/// roster, dialed again after each loss; the data connection is opened when bytes are needed and closed
/// once no request has started on it for `dataIdle` and none is in flight.
actor PeerLink {
  private let peer: PairedPeer
  private let me: Machine
  private let key: DeviceKey
  private let access: RelayAccess
  private let report: @Sendable (PeerEvent) async -> Void
  private(set) var link = Link.reconnecting
  private var control: CallerSession?
  private var data: CallerSession?
  private var dialingData: Task<CallerSession?, Never>?
  private var idleTimer: Task<Void, Never>?
  private var waiting: [Int: CheckedContinuation<CallerSession?, Never>] = [:]
  private var nextWaiter = 0
  private var running: Task<Void, Never>?
  private var isStopped = false

  init(
    peer: PairedPeer, me: Machine, key: DeviceKey, access: RelayAccess,
    report: @escaping @Sendable (PeerEvent) async -> Void
  ) {
    self.peer = peer
    self.me = me
    self.key = key
    self.access = access
    self.report = report
  }

  func start() {
    running = Task { await self.keepConnected() }
  }

  func stop() async {
    isStopped = true
    running?.cancel()
    dialingData?.cancel()
    idleTimer?.cancel()
    for waiter in waiting.values { waiter.resume(returning: nil) }
    waiting = [:]
    await control?.close()
    await data?.close()
    control = nil
    data = nil
  }

  /// Tells the Mac it was removed, if it can be reached now.
  func sayUnpaired() async {
    await control?.send(.unpaired)
  }

  /// The control connection if there is one now.
  var currentControl: CallerSession? { control }

  /// Waits for the control connection; `nil` once the link is stopped or the waiting task is cancelled.
  func nextControl() async -> CallerSession? {
    if let control { return control }
    if isStopped { return nil }
    nextWaiter += 1
    let id = nextWaiter
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else { return continuation.resume(returning: nil) }
        waiting[id] = continuation
      }
    } onCancel: {
      Task { await self.stopWaiting(id) }
    }
  }

  private func stopWaiting(_ id: Int) {
    waiting.removeValue(forKey: id)?.resume(returning: nil)
  }

  /// The connection for a lane, opening the data connection if needed. While the control connection is
  /// being dialed, waits for it as long as one dial may take; `nil` once the Mac is known to be offline.
  func session(for lane: Lane) async -> CallerSession? {
    guard let control = await controlSoon() else { return nil }
    guard lane == .data else { return control }
    if let data {
      restartIdleTimer(for: data)
      return data
    }
    if let dialingData { return await dialingData.value }
    let dialing = Task { try? await self.dial(.data) }
    dialingData = dialing
    let opened = await dialing.value
    dialingData = nil
    guard !isStopped, let opened else { return nil }
    data = opened
    restartIdleTimer(for: opened)
    Task {
      await opened.ended()
      self.dataEnded(opened)
    }
    return opened
  }

  private func restartIdleTimer(for session: CallerSession) {
    idleTimer?.cancel()
    let clock = access.clock
    let idle = access.dataIdle
    idleTimer = Task {
      guard (try? await clock.sleep(for: idle)) != nil else { return }
      await self.closeIfIdle(session)
    }
  }

  private func closeIfIdle(_ session: CallerSession) async {
    guard data === session else { return }
    if await session.isBusy {
      restartIdleTimer(for: session)
      return
    }
    data = nil
    idleTimer = nil
    await session.close()
  }

  private func controlSoon() async -> CallerSession? {
    if let control { return control }
    guard link == .reconnecting, !isStopped else { return nil }
    let limit = access.heartbeat.dialTimeout * 2
    let clock = access.clock
    return await withTaskGroup(of: CallerSession?.self) { group in
      group.addTask { await self.nextControl() }
      group.addTask {
        try? await clock.sleep(for: limit)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }

  private func dataEnded(_ session: CallerSession) {
    guard data === session else { return }
    data = nil
    idleTimer?.cancel()
    idleTimer = nil
  }

  private func keepConnected() async {
    var attempt = 0
    while !Task.isCancelled, !isStopped {
      do throws(GreetingError) {
        let session = try await dial(.control)
        attempt = 0
        await connected(session)
        await session.ended()
        await lost(session)
      } catch .refused(.unknown) {
        await report(.refused)
        return
      } catch {
        await set(.offline)
      }
      guard await access.pause(attempt: attempt) else { return }
      attempt += 1
    }
  }

  private func dial(_ lane: Lane) async throws(GreetingError) -> CallerSession {
    let socket: any MessageSocket
    do {
      socket = try await access.open(peer.address)
    } catch {
      throw .channel(.socket(error))
    }
    let greeted = try await Greeting.dial(socket, as: key, me: me, to: peer.address, purpose: .open(lane))
    let report = report
    let session = CallerSession(channel: greeted.channel) { await report(.unpaired) }
    await session.start()
    return session
  }

  private func connected(_ session: CallerSession) async {
    guard !isStopped else {
      await session.close()
      return
    }
    control = session
    for waiter in waiting.values { waiter.resume(returning: session) }
    waiting = [:]
    await set(.connected)
  }

  private func lost(_ session: CallerSession) async {
    guard control === session else { return }
    control = nil
    await data?.close()
    data = nil
    if !isStopped { await set(.reconnecting) }
  }

  private func set(_ link: Link) async {
    guard self.link != link else { return }
    self.link = link
    await report(.link(link))
  }
}
