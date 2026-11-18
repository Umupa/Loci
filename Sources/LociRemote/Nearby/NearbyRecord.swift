import Foundation
import LociModel

/// What a Mac tells the local network about itself in its Bonjour TXT record: enough to be listed and
/// dialed through the relay. The Mac's id is not sent; it is the fingerprint of the key.
enum NearbyRecord {
  static let serviceType = "_loci._tcp"

  static func entries(of mac: NearbyMac) -> [String: String] {
    [
      "n": mac.name, "m": mac.model.rawValue, "t": mac.address.routeToken,
      "k": Base64URL.encode(mac.address.publicKey),
    ]
  }

  static func mac(from entries: [String: String]) -> NearbyMac? {
    guard let name = entries["n"], !name.isEmpty, let token = entries["t"],
      let key = entries["k"].flatMap(Base64URL.decode), let address = PeerAddress(routeToken: token, publicKey: key)
    else { return nil }
    return NearbyMac(name: name, model: entries["m"].flatMap(MachineModel.init(rawValue:)) ?? .other, address: address)
  }
}
