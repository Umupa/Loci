import Foundation
import LociModel
import LociRemote
import LociStore

/// Serves this Mac's host to the paired Macs that open it. A session lasts until its connection ends or
/// its Mac is removed, which ends every session of that Mac at once.
actor Gateway {
  private let host: any LociModel.Host
  private let folder: MachineFolder
  private let newID: @Sendable () -> EntityID
  private let unpaired: @Sendable (MachineID) async -> Void
  private var sessions: [MachineID: [ObjectIdentifier: GatewaySession]] = [:]

  /// `unpaired` runs when a Mac says it removed this one.
  init(
    host: any LociModel.Host, folder: MachineFolder, newID: @escaping @Sendable () -> EntityID,
    unpaired: @escaping @Sendable (MachineID) async -> Void
  ) {
    self.host = host
    self.folder = folder
    self.newID = newID
    self.unpaired = unpaired
  }

  /// Serves one connection until it ends.
  func serve(_ greeted: Greeted) async {
    let session = GatewaySession(
      peer: greeted.peer.id, channel: greeted.channel, host: host, folder: folder, newID: newID, unpaired: unpaired)
    let key = ObjectIdentifier(session)
    sessions[greeted.peer.id, default: [:]][key] = session
    await session.serve()
    sessions[greeted.peer.id]?[key] = nil
  }

  /// Tells a removed Mac it was removed and closes all its connections.
  func disconnect(_ peer: MachineID) async {
    for session in (sessions.removeValue(forKey: peer) ?? [:]).values { await session.unpair() }
  }

  func sessionCount(of peer: MachineID) -> Int {
    sessions[peer]?.count ?? 0
  }
}
