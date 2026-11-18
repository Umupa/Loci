import Foundation
import LociModel
import LociRemote
import LociStore
import os

/// The Macs this one is paired with, served and opened through the relay. This Mac registers with the
/// relay so paired Macs can open it, keeps a connection to each paired Mac so the roster shows who is
/// reachable, and announces itself on the local network so a Mac nearby can ask to pair.
public actor MachinesService: Machines {
  public nonisolated let this: Machine
  nonisolated let local: any LociModel.Host
  nonisolated let folder: MachineFolder
  let key: DeviceKey
  let access: RelayAccess
  let discovery: any NearbyDiscovery
  let sleepGuard: any SleepGuard
  let now: @Sendable () -> Timestamp
  let newID: @Sendable () -> EntityID
  let makeSecret: @Sendable () -> Data
  private(set) var gateway: Gateway?

  private(set) var peers: [PairedPeer]
  private var links: [MachineID: PeerLink] = [:]
  private var linkStates: [MachineID: Link] = [:]
  private var rosterWatchers: [Int: AsyncStream<Roster>.Continuation] = [:]
  private var nextWatcher = 0
  var pending: [EntityID: PendingRequest] = [:]
  var requestWatchers: [Int: AsyncStream<[PairingRequest]>.Continuation] = [:]
  var invites = IssuedInvites()
  /// Invites whose handshake is done, waiting for the other Mac to confirm.
  var redeemed: [EntityID: IssuedInvites.Issued] = [:]
  /// The keys of the Macs whose pairing requests are being shown now.
  var asking: Set<Data> = []
  /// When each Mac's last pairing request was declined.
  var declined: [Data: Timestamp] = [:]
  private var running: [Task<Void, Never>] = []

  static let log = Logger(subsystem: "com.loci.native.dev", category: "machines")

  public init(
    this: Machine, key: DeviceKey, local: any LociModel.Host, access: RelayAccess, folder: MachineFolder,
    discovery: any NearbyDiscovery, sleepGuard: any SleepGuard, now: @escaping @Sendable () -> Timestamp,
    newID: @escaping @Sendable () -> EntityID,
    makeSecret: @escaping @Sendable () -> Data = { Data((0..<32).map { _ in UInt8.random(in: 0...255) }) }
  ) {
    self.this = this
    self.key = key
    self.local = local
    self.access = access
    self.folder = folder
    self.discovery = discovery
    self.sleepGuard = sleepGuard
    self.now = now
    self.newID = newID
    self.makeSecret = makeSecret
    peers = folder.roster()
  }

  /// Registers with the relay, connects to every paired Mac and announces this one nearby.
  public func start() async {
    try? folder.clearUploads()
    gateway = Gateway(host: local, folder: folder, newID: newID) { [weak self] peer in
      await self?.forget(peer, telling: false)
    }
    for peer in peers { await connect(peer) }
    await sleepGuard.keepAwake(!peers.isEmpty)
    let agent = RelayAgent(
      relay: access.relay, token: key.routeToken, dialer: access.dialer, heartbeat: access.heartbeat,
      backoff: access.backoff, clock: access.clock, random: access.random)
    running.append(
      Task { [weak self] in
        for await event in agent.run() { await self?.handle(event) }
      })
    let nearby = NearbyMac(name: this.name, model: this.model, address: key.address)
    let discovery = discovery
    running.append(Task { await discovery.advertise(nearby) })
  }

  /// Stops serving and closes every connection.
  public func stop() async {
    for task in running { task.cancel() }
    running = []
    for link in links.values { await link.stop() }
    links = [:]
  }

  public nonisolated func roster() -> AsyncStream<Roster> {
    let (roster, continuation) = AsyncStream.makeStream(of: Roster.self, bufferingPolicy: .bufferingNewest(1))
    Task { await self.watchRoster(continuation) }
    return roster
  }

  public nonisolated func open(_ machine: MachineID) -> any LociModel.Host {
    guard machine != this.id else { return local }
    return RemoteHost(
      machine: machine, folder: folder, link: { [weak self] in await self?.links[machine] },
      keep: { [weak self] body, name, request in await self?.keep(body, as: name, request: request, on: machine) })
  }

  func link(to machine: MachineID) -> PeerLink? {
    links[machine]
  }

  public func remove(_ machine: MachineID) async {
    await forget(machine, telling: true)
  }

  private func watchRoster(_ continuation: AsyncStream<Roster>.Continuation) {
    nextWatcher += 1
    let id = nextWatcher
    rosterWatchers[id] = continuation
    continuation.yield(currentRoster)
    continuation.onTermination = { _ in Task { await self.dropRosterWatcher(id) } }
  }

  private func dropRosterWatcher(_ id: Int) {
    rosterWatchers[id] = nil
  }

  private var currentRoster: Roster {
    Roster(
      this: this,
      paired: peers.map { PairedMachine(machine: $0.machine, link: linkStates[$0.machine.id] ?? .reconnecting) })
  }

  func publishRoster() {
    let roster = currentRoster
    for watcher in rosterWatchers.values { watcher.yield(roster) }
  }

  func allocateWatcher() -> Int {
    nextWatcher += 1
    return nextWatcher
  }

  /// Adds a Mac that was just paired, or updates its name and address if it was already there.
  func add(_ machine: Machine, at address: PeerAddress) async {
    let peer = PairedPeer(machine: machine, address: address, pairedAt: now())
    if let index = peers.firstIndex(where: { $0.machine.id == machine.id }) {
      peers[index] = peer
      await links.removeValue(forKey: machine.id)?.stop()
    } else {
      peers.append(peer)
    }
    save()
    await connect(peer)
    await sleepGuard.keepAwake(true)
    publishRoster()
  }

  func isPaired(_ hello: Hello) -> Bool {
    peers.contains { $0.machine.id == hello.from.id && $0.address.publicKey == hello.address.publicKey }
  }

  private func connect(_ peer: PairedPeer) async {
    let id = peer.machine.id
    let link = PeerLink(peer: peer, me: this, key: key, access: access) { [weak self] event in
      await self?.handle(event, from: id)
    }
    links[id] = link
    await link.start()
  }

  private func handle(_ event: PeerEvent, from machine: MachineID) async {
    switch event {
    case .link(let link):
      guard links[machine] != nil else { return }
      linkStates[machine] = link
      publishRoster()
    case .refused, .unpaired:
      await forget(machine, telling: false)
    }
  }

  private func handle(_ event: AgentEvent) async {
    switch event {
    case .registered(let proto):
      Self.log.notice("registered with the relay, protocol \(proto, privacy: .public)")
    case .connection(let socket):
      Task { await self.answer(socket) }
    case .disconnected(let reason):
      Self.log.notice("lost the relay: \(String(describing: reason), privacy: .public)")
    case .stopped(let reason):
      Self.log.error("stopped serving through the relay: \(String(describing: reason), privacy: .public)")
    }
  }

  /// Removes a Mac: its connections close at once, and it is told when `telling`.
  ///
  /// Everything that says the Mac is gone changes before the first suspension, so nobody who sees the
  /// roster without it can still read what was kept of it.
  private func forget(_ machine: MachineID, telling: Bool) async {
    guard let index = peers.firstIndex(where: { $0.machine.id == machine }) else { return }
    peers.remove(at: index)
    save()
    let link = links.removeValue(forKey: machine)
    linkStates[machine] = nil
    try? folder.forget(machine)
    publishRoster()
    if telling { await link?.sayUnpaired() }
    await link?.stop()
    await gateway?.disconnect(machine)
    await sleepGuard.keepAwake(!peers.isEmpty)
  }

  /// Keeps what was seen of a Mac for reading while it is offline, unless it has left the roster: a reply
  /// that arrives after the Mac was removed must not bring its cache back.
  func keep(_ body: Data, as name: String, request: Data, on machine: MachineID) {
    guard peers.contains(where: { $0.machine.id == machine }) else { return }
    try? folder.cache(body, as: name, request: request, on: machine)
  }

  private func save() {
    do {
      try folder.saveRoster(peers)
    } catch {
      Self.log.error("could not save the roster: \(error.localizedDescription, privacy: .public)")
    }
  }
}
