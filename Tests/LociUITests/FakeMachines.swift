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

  let paired: [PairedMachine]
  let hosts: [MachineID: any LociModel.Host]
  let nearbyMacs: [NearbyMac]
  let waiting: [PairingRequest]
  let removed = Mutex<[MachineID]>([])
  /// `accept` waits for the other Mac until it is cancelled, then says so here.
  let acceptWaits: Bool
  let acceptStarted = Mutex(false)
  let acceptCancelled = Mutex(false)

  /// Counts what the window asks of these Macs; the fake hosts given here should share it.
  let activity: Activity

  /// `hosts` serve each Mac's data, this one's included.
  init(
    paired: [PairedMachine] = [], hosts: [MachineID: any LociModel.Host], nearby: [NearbyMac] = [],
    requests: [PairingRequest] = [], acceptWaits: Bool = false, activity: Activity = Activity()
  ) {
    self.activity = activity
    self.acceptWaits = acceptWaits
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

  static let invite = Invite(
    id: EntityID(), name: "MacBook Pro", model: .laptop, address: address(key: 1), secret: Data(count: 32),
    expires: Timestamp(Date.now.addingTimeInterval(600)))!

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
    return Self.invite
  }

  func accept(_ invite: Invite) async throws(PairingFailure) -> Machine {
    guard acceptWaits else { return invite.from }
    acceptStarted.withLock { $0 = true }
    try? await Task.sleep(for: .seconds(60))
    acceptCancelled.withLock { $0 = Task.isCancelled }
    throw .unreachable
  }

  func remove(_ machine: MachineID) async {
    removed.withLock { $0.append(machine) }
  }
}
