/// The Macs the window can show, and pairing new ones. The interface knows nothing else about the network.
public protocol Machines: Sendable {
  /// The roster now, then again whenever a Mac is paired or removed or its link changes.
  func roster() -> AsyncStream<Roster>
  /// The host behind a Mac's data; the same id always gives the same host. A Mac that is not in the roster
  /// gives a host whose commands fail with `HostError.offline`.
  func open(_ machine: MachineID) -> any Host
  /// Searches the local network for as long as the stream is held.
  func nearby() -> AsyncStream<[NearbyMac]>
  /// Asks a nearby Mac to pair. Dropping the stream cancels the pairing on both Macs.
  func pair(with mac: NearbyMac) -> AsyncStream<PairingStep>
  /// The requests waiting for an answer, again whenever one arrives, is answered, or is withdrawn.
  func requests() -> AsyncStream<[PairingRequest]>
  func answer(_ request: PairingRequest.ID, allow: Bool) async
  /// A new link for another Mac to paste. It works once, until it expires.
  func invite() async throws(PairingFailure) -> Invite
  /// Pairs with the Mac that made the link.
  func accept(_ invite: Invite) async throws(PairingFailure) -> Machine
  /// Forgets the Mac at once, closes its connections, and tells it if it can be reached.
  func remove(_ machine: MachineID) async
}
