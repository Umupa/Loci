import Foundation

/// A value written to JSON as its text form, which must parse back to the same value.
protocol TextCodable: Codable, LosslessStringConvertible {}

extension TextCodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let value = Self(text) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a valid \(Self.self): \(text)")
    }
    self = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}
