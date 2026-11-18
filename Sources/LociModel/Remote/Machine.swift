import CryptoKit
import Foundation

/// A Mac's identity: the fingerprint of its device key, stable for as long as the key is.
public struct MachineID: Hashable, Sendable, TextCodable {
  /// Lowercase hex of the first 16 bytes of the SHA-256 of the device's public key.
  public let fingerprint: String

  public init(publicKey: Data) {
    fingerprint = SHA256.hash(data: publicKey).prefix(16).map { String(format: "%02x", $0) }.joined()
  }

  /// Parses a fingerprint as `description` writes it: exactly 32 lowercase hex digits.
  public init?(_ fingerprint: String) {
    guard fingerprint.wholeMatch(of: /[0-9a-f]{32}/) != nil else { return nil }
    self.fingerprint = fingerprint
  }

  public var description: String { fingerprint }
}

/// What kind of Mac it is, which decides its icon.
public enum MachineModel: String, Hashable, Codable, Sendable, CaseIterable {
  case laptop, mini, iMac, studio, pro, other
}

/// A Mac whose courses, library and mentors the window can show.
public struct Machine: Hashable, Codable, Sendable, Identifiable {
  public let id: MachineID
  public let name: String
  public let model: MachineModel

  public init(id: MachineID, name: String, model: MachineModel) {
    self.id = id
    self.name = name
    self.model = model
  }
}

/// How a paired Mac can be reached right now.
public enum Link: Hashable, Sendable {
  case connected
  /// It was reachable a moment ago and is being dialed again.
  case reconnecting
  /// It is not on the relay: asleep, quit, or this Mac has no network.
  case offline
}

/// A Mac in the roster with how it can be reached.
public struct PairedMachine: Hashable, Sendable, Identifiable {
  public let machine: Machine
  public let link: Link

  public init(machine: Machine, link: Link) {
    self.machine = machine
    self.link = link
  }

  public var id: MachineID { machine.id }
}

/// This Mac and the Macs paired with it, in menu order.
public struct Roster: Hashable, Sendable {
  public let this: Machine
  public let paired: [PairedMachine]

  public init(this: Machine, paired: [PairedMachine]) {
    self.this = this
    self.paired = paired
  }
}

/// How another Mac is reached through the relay and recognized when it answers.
public struct PeerAddress: Hashable, Sendable {
  /// The relay routes `/c/<routeToken>/…` to the Mac; 43 base64url characters.
  public let routeToken: String
  /// The Mac's Curve25519 public key, 32 bytes.
  public let publicKey: Data

  public init?(routeToken: String, publicKey: Data) {
    guard routeToken.wholeMatch(of: /[A-Za-z0-9_-]{43}/) != nil, publicKey.count == 32 else { return nil }
    self.routeToken = routeToken
    self.publicKey = publicKey
  }
}

extension PeerAddress: Codable {
  private enum CodingKeys: String, CodingKey { case routeToken, publicKey }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let token = try container.decode(String.self, forKey: .routeToken)
    guard let key = Base64URL.decode(try container.decode(String.self, forKey: .publicKey)),
      let address = PeerAddress(routeToken: token, publicKey: key)
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .routeToken, in: container, debugDescription: "Not a relay address")
    }
    self = address
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(routeToken, forKey: .routeToken)
    try container.encode(Base64URL.encode(publicKey), forKey: .publicKey)
  }
}

/// A Mac on the same network running Loci, not yet paired.
public struct NearbyMac: Hashable, Sendable, Identifiable {
  public let machine: Machine
  public let address: PeerAddress

  /// The Mac's id is the fingerprint of the address's key, so the two cannot disagree.
  public init(name: String, model: MachineModel, address: PeerAddress) {
    machine = Machine(id: MachineID(publicKey: address.publicKey), name: name, model: model)
    self.address = address
  }

  public var id: MachineID { machine.id }
  public var name: String { machine.name }
  public var model: MachineModel { machine.model }
}
