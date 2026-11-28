import Foundation
import LociModel
import LociRemote
import LociStore

extension MachinesService {
  /// The service on this Mac's network, with its key from `secrets` (made the first time). `nil` when
  /// the key cannot be read or kept, which leaves the app without remote access rather than with a key
  /// that changes on every launch.
  public static func onThisMac(
    relay address: URL, registrationKey: String, local: any LociModel.Host, support: URL, secrets: Secrets
  ) -> MachinesService? {
    let key: DeviceKey
    do {
      key = try deviceKey(in: secrets.folder)
    } catch {
      log.error("no device key: \(String(describing: error), privacy: .public)")
      return nil
    }
    return MachinesService(
      this: Machine(id: key.machineID, name: ThisMac.name, model: ThisMac.model), key: key, local: local,
      access: RelayAccess(relay: Relay(address: address, registrationKey: registrationKey), dialer: NetworkDialer()),
      folder: MachineFolder(root: support), discovery: BonjourDiscovery(), sleepGuard: PowerAssertion(),
      now: { Timestamp(.now) }, newID: { EntityID() })
  }

  static func deviceKey(in vault: any KeyVault) throws -> DeviceKey {
    if let stored = try vault.load() { return try DeviceKey(rawRepresentation: stored) }
    let key = try DeviceKey()
    try vault.save(key.rawRepresentation)
    return key
  }
}
