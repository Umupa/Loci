import Foundation
import LociModel
import Synchronization

@testable import LociUI

/// Macs with fixed sample data: this one, and the ones paired with it in whatever state a test needs.
final class FakeMachines: Machines {
  static let thisMac = Machine(id: id(1), name: "MacBook Pro", model: .laptop)
  static let studio = Machine(id: id(2), name: "Mac Studio", model: .studio)
  static let mini = Machine(id: id(3), name: "Mac mini", model: .mini)
  static let iMac = Machine(id: id(4), name: "iMac", model: .iMac)

  let availability: RemoteAvailability
  let paired: [PairedMachine]
  let hosts: [MachineID: any LociModel.Host]
  let nearbyMacs: [NearbyMac]
  let waiting: [PairingRequest]
  let removed = Mutex<[MachineID]>([])
  /// `accept` waits for the other Mac until it is cancelled, then says so here.
  let acceptWaits: Bool
  let acceptFailure: PairingFailure?
  let acceptStarted = Mutex(false)
  let acceptCancelled = Mutex(false)
  let acceptedInvites = Mutex<[Invite]>([])

  /// Counts what the window asks of these Macs; the fake hosts given here should share it.
  let activity: Activity
  private let now: @Sendable () -> Date

  /// `hosts` serve each Mac's data, this one's included.
  init(
    availability: RemoteAvailability = .available, paired: [PairedMachine] = [], hosts: [MachineID: any LociModel.Host],
    nearby: [NearbyMac] = [], requests: [PairingRequest] = [], acceptWaits: Bool = false,
    acceptFailure: PairingFailure? = nil, activity: Activity = Activity(),
    now: @escaping @Sendable () -> Date = { .now }
  ) {
    self.availability = availability
    self.activity = activity
    self.now = now
    self.acceptWaits = acceptWaits
    self.acceptFailure = acceptFailure
    self.paired = paired
    self.hosts = hosts
    self.nearbyMacs = nearby
    self.waiting = requests
  }

  static func id(_ byte: UInt8) -> MachineID {
    MachineID(publicKey: Data(repeating: byte, count: 32))
  }

  static func nearby(_ name: String, _ model: MachineModel, key: UInt8) -> NearbyMac {
    NearbyMac(name: name, model: model, address: address(key: key))
  }

  static func address(key: UInt8) -> PeerAddress {
    PeerAddress(routeToken: Base64URL.encode(Data(count: 32)), publicKey: Data(repeating: key, count: 32))!
  }

  static func invite(issuedAt: Date, from: Machine = studio, key: UInt8 = 2) -> Invite {
    Invite(
      id: EntityID(), name: from.name, model: from.model, address: address(key: key), secret: Data(count: 32),
      expires: Timestamp(issuedAt.addingTimeInterval(600)))!
  }

  static let code = PairingCode(4827)

  func roster() -> AsyncStream<Roster> {
    let roster = Roster(this: Self.thisMac, paired: paired)
    return AsyncStream { $0.yield(roster) }
  }

  func open(_ machine: MachineID) -> any LociModel.Host {
    hosts[machine] ?? UnreachableHost()
  }

  func nearby() -> AsyncStream<[NearbyMac]> {
    let found = nearbyMacs
    return AsyncStream { $0.yield(found) }
  }

  func pair(with mac: NearbyMac) -> AsyncStream<PairingStep> {
    AsyncStream { $0.yield(.code(Self.code)) }
  }

  func requests() -> AsyncStream<[PairingRequest]> {
    let waiting = waiting
    return AsyncStream { $0.yield(waiting) }
  }

  func answer(_ request: PairingRequest.ID, allow: Bool) async {}

  func invite() async throws(PairingFailure) -> Invite {
    activity.begin()
    defer { activity.end() }
    return Self.invite(issuedAt: now())
  }

  func accept(_ invite: Invite) async throws(PairingFailure) -> Machine {
    if acceptWaits {
      acceptStarted.withLock { $0 = true }
      try? await Task.sleep(for: .seconds(60))
      acceptCancelled.withLock { $0 = Task.isCancelled }
      throw .unreachable
    }
    guard availability == .available else { throw .unreachable }
    guard !invite.hasExpired(at: Timestamp(now())) else { throw .expired }
    guard invite.from.id != Self.thisMac.id else { throw .selfInvite }
    if let acceptFailure { throw acceptFailure }
    acceptedInvites.withLock { $0.append(invite) }
    return invite.from
  }

  func remove(_ machine: MachineID) async {
    removed.withLock { $0.append(machine) }
  }
}
