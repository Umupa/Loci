import Foundation

/// A time-ordered identifier (UUID version 7) shared by every stored entity.
///
/// Identifiers created later sort after earlier ones, so a folder listing or a
/// database index is already in creation order.
public struct EntityID: Hashable, Sendable {
  public let uuid: UUID

  /// Creates an identifier for the current moment.
  public init() {
    var entropy = SystemRandomNumberGenerator()
    self.init(at: .now, entropy: &entropy)
  }

  /// Creates an identifier for `instant`, drawing its random bits from `entropy`.
  public init(at instant: Date, entropy: inout some RandomNumberGenerator) {
    let milliseconds = UInt64(max(0, instant.timeIntervalSince1970 * 1000))
    let high = (milliseconds << 16) | 0x7000 | (entropy.next() & 0x0FFF)
    let low = 0x8000_0000_0000_0000 | (entropy.next() & 0x3FFF_FFFF_FFFF_FFFF)
    self.uuid = UUID(high: high, low: low)
  }

  /// The moment this identifier was created, to the millisecond.
  public var createdAt: Date {
    Date(timeIntervalSince1970: Double(uuid.high >> 16) / 1000)
  }
}

extension EntityID: Comparable {
  public static func < (lhs: EntityID, rhs: EntityID) -> Bool {
    (lhs.uuid.high, lhs.uuid.low) < (rhs.uuid.high, rhs.uuid.low)
  }
}

extension EntityID: LosslessStringConvertible {
  /// Parses the canonical form. Returns `nil` for anything that is not a version 7 UUID.
  public init?(_ description: String) {
    guard let uuid = UUID(uuidString: description), (uuid.high >> 12) & 0xF == 7 else { return nil }
    self.uuid = uuid
  }

  public var description: String { uuid.uuidString.lowercased() }
}

extension EntityID: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let id = EntityID(text) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a version 7 UUID: \(text)")
    }
    self = id
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

extension UUID {
  fileprivate init(high: UInt64, low: UInt64) {
    var bytes = [UInt8](repeating: 0, count: 16)
    for index in 0..<8 {
      bytes[index] = UInt8(truncatingIfNeeded: high >> (56 - 8 * UInt64(index)))
      bytes[index + 8] = UInt8(truncatingIfNeeded: low >> (56 - 8 * UInt64(index)))
    }
    self = bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
  }

  fileprivate var high: UInt64 { half(startingAt: 0) }
  fileprivate var low: UInt64 { half(startingAt: 8) }

  private func half(startingAt offset: Int) -> UInt64 {
    withUnsafeBytes(of: uuid) { bytes in
      bytes[offset..<offset + 8].reduce(0) { $0 << 8 | UInt64($1) }
    }
  }
}
