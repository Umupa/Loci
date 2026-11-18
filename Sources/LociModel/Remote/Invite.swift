import CryptoKit
import Foundation

/// A one-time link that pairs whoever pastes it with the Mac that made it.
///
/// The link carries everything needed to reach that Mac and prove the link was seen: its relay address, a
/// secret the handshake mixes in, and when the link stops working.
public struct Invite: Hashable, Sendable {
  public let id: EntityID
  public let from: Machine
  public let address: PeerAddress
  /// 32 bytes; the pre-shared key of the handshake.
  public let secret: Data
  public let expires: Timestamp

  /// The Mac's id is the fingerprint of the address's key, so the two cannot disagree.
  public init?(
    id: EntityID, name: String, model: MachineModel, address: PeerAddress, secret: Data, expires: Timestamp
  ) {
    guard secret.count == Self.secretLength, !name.isEmpty, name.utf8.count <= Self.longestName else { return nil }
    self.id = id
    self.from = Machine(id: MachineID(publicKey: address.publicKey), name: name, model: model)
    self.address = address
    self.secret = secret
    self.expires = expires
  }

  /// Recognizes a pasted `loci://pair/…`, ignoring white space around it; `nil` for anything else,
  /// including a link that was cut short or changed.
  public init?(pasted: String) {
    let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.hasPrefix(Self.prefix), let payload = Base64URL.decode(String(text.dropFirst(Self.prefix.count)))
    else { return nil }
    self.init(payload: payload)
  }

  /// `loci://pair/…`, to copy and paste into Loci on another Mac.
  public var link: String {
    Self.prefix + Base64URL.encode(payload)
  }

  public func hasExpired(at now: Timestamp) -> Bool {
    now >= expires
  }

  static let prefix = "loci://pair/"
  static let version: UInt8 = 1
  static let secretLength = 32
  static let longestName = 200
}

extension Invite {
  /// The body, then the first 4 bytes of its SHA-256, so a link cut short or mistyped is not mistaken for
  /// a different one.
  private var payload: Data {
    body + Self.checksum(of: body)
  }

  /// version · public key · route token · id · secret · expiry (ms, big-endian) · model · name (UTF-8)
  private var body: Data {
    var bytes = Data([Self.version])
    bytes.append(address.publicKey)
    bytes.append(Base64URL.decode(address.routeToken) ?? Data())
    bytes.append(contentsOf: withUnsafeBytes(of: id.uuid.uuid) { Array($0) })
    bytes.append(secret)
    bytes.append(contentsOf: withUnsafeBytes(of: expires.millisecondsSince1970.bigEndian) { Array($0) })
    bytes.append(UInt8(MachineModel.allCases.firstIndex(of: from.model) ?? 0))
    bytes.append(Data(from.name.utf8))
    return bytes
  }

  private static func checksum(of body: Data) -> Data {
    Data(SHA256.hash(data: body).prefix(4))
  }

  private init?(payload: Data) {
    guard payload.count > 4 else { return nil }
    let body = payload.dropLast(4)
    guard Self.checksum(of: Data(body)) == payload.suffix(4) else { return nil }
    var reader = ByteReader(Array(body))
    guard reader.byte() == Self.version,
      let key = reader.bytes(32), let token = reader.bytes(32), let uuid = reader.bytes(16),
      let secret = reader.bytes(Self.secretLength), let expiry = reader.bytes(8), let modelIndex = reader.byte(),
      let id = EntityID(UUID(uuid: uuid.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) }).uuidString),
      let address = PeerAddress(routeToken: Base64URL.encode(Data(token)), publicKey: Data(key)),
      MachineModel.allCases.indices.contains(Int(modelIndex)),
      let name = String(bytes: reader.rest, encoding: .utf8)
    else { return nil }
    let milliseconds = expiry.reduce(Int64(0)) { $0 << 8 | Int64($1) }
    self.init(
      id: id, name: name, model: MachineModel.allCases[Int(modelIndex)], address: address, secret: Data(secret),
      expires: Timestamp(millisecondsSince1970: milliseconds))
  }
}

private struct ByteReader {
  private let bytes: [UInt8]
  private var offset = 0

  init(_ bytes: [UInt8]) {
    self.bytes = bytes
  }

  mutating func byte() -> UInt8? {
    self.bytes(1)?.first
  }

  mutating func bytes(_ count: Int) -> [UInt8]? {
    guard offset + count <= bytes.count else { return nil }
    defer { offset += count }
    return Array(bytes[offset..<offset + count])
  }

  var rest: [UInt8] { Array(bytes[offset...]) }
}
