import Foundation
import LociModel

/// The Macs a window can show when this Mac pairs with none: there is no relay to reach another one.
public struct SingleMachine: Machines {
  public let availability: RemoteAvailability
  private let this: Machine
  private let host: any LociModel.Host

  /// `host` serves this Mac, the only one there is. Without a relay this Mac has no device key, so no other Mac
  /// could know it by one; its id here is the fingerprint of an empty key, which only tells it apart within this
  /// window and is never stored or sent.
  public init(
    name: String, model: MachineModel, host: any LociModel.Host, availability: RemoteAvailability = .missingRelay
  ) {
    self.availability = availability
    this = Machine(id: MachineID(publicKey: Data()), name: name, model: model)
    self.host = host
  }

  public func roster() -> AsyncStream<Roster> {
    AsyncStream { $0.yield(Roster(this: this, paired: [])) }
  }

  public func open(_ machine: MachineID) -> any LociModel.Host {
    machine == this.id ? host : UnreachableHost()
  }

  public func nearby() -> AsyncStream<[NearbyMac]> {
    AsyncStream { $0.yield([]) }
  }

  public func pair(with mac: NearbyMac) -> AsyncStream<PairingStep> {
    AsyncStream {
      $0.yield(.failed(.unreachable))
      $0.finish()
    }
  }

  public func requests() -> AsyncStream<[PairingRequest]> {
    AsyncStream { $0.yield([]) }
  }

  public func answer(_ request: PairingRequest.ID, allow: Bool) async {}

  public func invite() async throws(PairingFailure) -> Invite {
    throw .unreachable
  }

  public func accept(_ invite: Invite) async throws(PairingFailure) -> Machine {
    throw .unreachable
  }

  public func remove(_ machine: MachineID) async {}
}

/// The host of a Mac that cannot be reached: nothing to read, nothing to change.
struct UnreachableHost: LociModel.Host {
  func run<C: Command>(_ command: C) async throws(HostError) -> C.Reply {
    throw .offline
  }

  func subscribe<S: Subscription>(_ subscription: S) -> AsyncStream<Feed<S.Value>> {
    AsyncStream {
      $0.yield(.unavailable(.offline))
      $0.finish()
    }
  }

  func upload(_ file: LocalFile) async throws(HostError) -> Upload {
    throw .offline
  }

  func localFile(_ place: LocalPlace) async -> LocalFile? { nil }
}
