import Foundation

/// A JSON value as a tree, so two versions of a subscription's value can be compared part by part.
public indirect enum JSON: Hashable, Sendable {
  case null
  case bool(Bool)
  case integer(Int64)
  case number(Double)
  case string(String)
  case array([JSON])
  case object([String: JSON])

  /// The JSON of an encodable value, with keys sorted.
  public init(encoding value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    self = try JSONDecoder().decode(JSON.self, from: encoder.encode(value))
  }

  public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
    try JSONDecoder().decode(type, from: data())
  }

  public func data() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(self)
  }
}

extension JSON: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSON].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSON].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}
