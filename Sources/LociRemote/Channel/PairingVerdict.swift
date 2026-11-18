import Foundation

/// The only message on a pairing channel: the person on the Mac being asked said yes or no.
public enum PairingVerdict: String, Hashable, Codable, Sendable {
  case allowed
  case declined

  public var encoded: Data { Data(rawValue.utf8) }

  public init?(_ data: Data) {
    self.init(rawValue: String(decoding: data, as: UTF8.self))
  }
}
