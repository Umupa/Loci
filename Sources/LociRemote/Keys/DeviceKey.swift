import CryptoKit
import Foundation
import LociModel

/// This Mac's Curve25519 key: who it is to every paired Mac, and where the relay finds it.
public struct DeviceKey: Sendable {
  public let privateKey: Curve25519.KeyAgreement.PrivateKey
  /// The route token is derived from the private key, so it is stable and only this Mac and the Macs it
  /// pairs with know it. The relay sees only its hash.
  public let address: PeerAddress

  public struct Unusable: Error, Hashable, Sendable {}

  public init(_ privateKey: Curve25519.KeyAgreement.PrivateKey = .init()) throws(Unusable) {
    let derived = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: privateKey.rawRepresentation), info: Data("loci route token".utf8),
      outputByteCount: 32)
    let token = Base64URL.encode(derived.withUnsafeBytes { Data($0) })
    guard let address = PeerAddress(routeToken: token, publicKey: privateKey.publicKey.rawRepresentation) else {
      throw Unusable()
    }
    self.privateKey = privateKey
    self.address = address
  }

  public init(rawRepresentation: Data) throws(Unusable) {
    guard let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawRepresentation) else {
      throw Unusable()
    }
    try self.init(key)
  }

  public var rawRepresentation: Data { privateKey.rawRepresentation }
  public var publicKey: Data { address.publicKey }
  public var machineID: MachineID { MachineID(publicKey: publicKey) }
  public var routeToken: String { address.routeToken }
}
