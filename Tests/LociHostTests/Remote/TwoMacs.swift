import Foundation
import LociModel
import LociRemote
import LociStore
import Synchronization
import Testing

@testable import LociHost

/// Two Macs in one process: each with its own Loci folder, host and roster, meeting through one
/// in-process relay and one shared local network.
struct TwoMacs {
  let relay: LoopbackRelay
  let studio: OneMac
  let laptop: OneMac
  let network: FakeLocalNetwork
  let setting: Setting

  /// What the Macs share besides the relay: their clocks, and the time they think it is.
  struct Setting: Sendable {
    var clock: any Clock<Duration> = ContinuousClock()
    var dataIdle: Duration = .seconds(60)
    let time = TestTime()
  }

  struct OneMac {
    let service: MachinesService
    let local: LocalHost
    let place: Place
    let machineFolder: MachineFolder
    let key: DeviceKey
    let awake: RecordedSleep
    var machine: Machine { service.this }
  }

  static let quick = Heartbeat(interval: .milliseconds(50), missesAllowed: 3, dialTimeout: .milliseconds(500))
  static let soon = Backoff(first: .milliseconds(10), longest: .milliseconds(50))

  /// A Mac, or the same Mac started again with its key, folder and roster when `reusing` is given.
  static func mac(
    _ name: String, model: MachineModel, relay: LoopbackRelay, network: FakeLocalNetwork, agent: FakeAgent,
    setting: Setting = Setting(), reusing earlier: OneMac? = nil
  ) async throws -> OneMac {
    let place = earlier?.place ?? Place()
    let local: LocalHost
    if let earlier {
      local = earlier.local
    } else {
      let world = TestWorld(agent: agent)
      local = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    }
    let key = try earlier?.key ?? DeviceKey()
    let folder = MachineFolder(root: place.root.appending(path: ".machines"))
    let awake = RecordedSleep()
    let service = MachinesService(
      this: Machine(id: key.machineID, name: name, model: model), key: key, local: local,
      access: RelayAccess(
        relay: relay.relay, dialer: relay, heartbeat: quick, backoff: soon, clock: setting.clock,
        dataIdle: setting.dataIdle),
      folder: folder, discovery: network, sleepGuard: awake, now: { [time = setting.time] in time.now },
      newID: { EntityID() })
    await service.start()
    await relay.registration(of: key.routeToken)
    return OneMac(service: service, local: local, place: place, machineFolder: folder, key: key, awake: awake)
  }

  /// Runs `body` with two Macs that are not paired yet, then stops both.
  static func with(
    agent: FakeAgent = FakeAgent(), relay: LoopbackRelay = LoopbackRelay(), setting: Setting = Setting(),
    _ body: (TwoMacs) async throws -> Void
  ) async throws {
    let network = FakeLocalNetwork()
    let studio = try await mac(
      "Mac Studio", model: .studio, relay: relay, network: network, agent: agent, setting: setting)
    let laptop = try await mac(
      "MacBook", model: .laptop, relay: relay, network: network, agent: agent, setting: setting)
    let macs = TwoMacs(relay: relay, studio: studio, laptop: laptop, network: network, setting: setting)
    do {
      try await body(macs)
    } catch {
      await macs.stop()
      throw error
    }
    await macs.stop()
  }

  func stop() async {
    for mac in [studio, laptop] {
      await mac.service.stop()
      await mac.local.close()
      mac.place.remove()
    }
  }

  /// Pairs the two through an invite the studio made, and waits until each sees the other connected.
  func pair() async throws {
    let invite = try await studio.service.invite()
    _ = try await laptop.service.accept(invite)
    #expect(await connected(laptop, to: studio))
    #expect(await connected(studio, to: laptop))
  }

  func connected(_ mac: OneMac, to other: OneMac, link: Link = .connected) async -> Bool {
    await roster(of: mac) { $0.paired.contains { $0.machine.id == other.machine.id && $0.link == link } } != nil
  }

  func roster(of mac: OneMac, within timeout: Duration = .seconds(5), where match: @escaping @Sendable (Roster) -> Bool)
    async -> Roster?
  {
    await firstOf(mac.service.roster(), within: timeout, where: match)
  }
}

/// The first element of a stream that matches, or `nil` after `timeout`.
func firstOf<Element: Sendable>(
  _ stream: AsyncStream<Element>, within timeout: Duration = .seconds(5),
  where match: @escaping @Sendable (Element) -> Bool
) async -> Element? {
  await withTaskGroup(of: Element?.self) { group in
    group.addTask {
      for await element in stream where match(element) { return element }
      return nil
    }
    group.addTask {
      try? await Task.sleep(for: timeout)
      return nil
    }
    let found = await group.next() ?? nil
    group.cancelAll()
    return found
  }
}

/// A local network where every Mac that announces itself is seen by every Mac that looks.
final class FakeLocalNetwork: NearbyDiscovery {
  private let announced = Mutex<[NearbyMac]>([])
  private let watchers = Mutex<[Int: AsyncStream<[NearbyMac]>.Continuation]>([:])
  private let counter = Mutex(0)

  func advertise(_ mac: NearbyMac) async {
    announced.withLock { $0.append(mac) }
    publish()
    try? await Task.sleep(for: .seconds(3600))
    announced.withLock { $0.removeAll { $0 == mac } }
    publish()
  }

  func browse() -> AsyncStream<[NearbyMac]> {
    let (macs, continuation) = AsyncStream.makeStream(of: [NearbyMac].self)
    let id = counter.withLock { count in
      count += 1
      return count
    }
    watchers.withLock { $0[id] = continuation }
    continuation.yield(announced.withLock { $0 })
    continuation.onTermination = { [weak self] _ in _ = self?.watchers.withLock { $0.removeValue(forKey: id) } }
    return macs
  }

  private func publish() {
    let macs = announced.withLock { $0 }
    for watcher in watchers.withLock({ Array($0.values) }) { watcher.yield(macs) }
  }
}

/// The time the Macs think it is, moved by hand.
final class TestTime: Sendable {
  private let current = Mutex(TestWorld.instant)

  var now: Timestamp { current.withLock { $0 } }

  func advance(seconds: Int64) {
    current.withLock { $0 = Timestamp(millisecondsSince1970: $0.millisecondsSince1970 + seconds * 1000) }
  }
}

/// Whether the Mac was last asked to stay awake.
actor RecordedSleep: SleepGuard {
  private(set) var isKeptAwake = false

  func keepAwake(_ awake: Bool) {
    isKeptAwake = awake
  }
}
