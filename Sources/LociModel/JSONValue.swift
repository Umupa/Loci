import Foundation

/// Any JSON value: what crosses to another Mac, what agent programs and MCP servers say, tool arguments and
/// schemas. Whole numbers are kept apart from the rest, so a value read and written again is the same.
public indirect enum JSONValue: Hashable, Sendable {
  case null
  case bool(Bool)
  case integer(Int64)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public subscript(key: String) -> JSONValue? {
    if case .object(let members) = self { members[key] } else { nil }
  }

  public var string: String? {
    if case .string(let value) = self { value } else { nil }
  }

  public var bool: Bool? {
    if case .bool(let value) = self { value } else { nil }
  }

  /// A whole number, written either way.
  public var int: Int? {
    switch self {
    case .integer(let value): Int(exactly: value)
    case .number(let value): Int(exactly: value.rounded()) == nil ? nil : Int(value.rounded())
    default: nil
    }
  }

  /// Any number, as a `Double`.
  public var number: Double? {
    switch self {
    case .integer(let value): Double(value)
    case .number(let value): value
    default: nil
    }
  }

  public var array: [JSONValue]? {
    if case .array(let values) = self { values } else { nil }
  }

  /// The JSON of an encodable value.
  public init(encoding value: some Encodable) throws {
    self = try JSONDecoder().decode(JSONValue.self, from: Self.encoder.encode(value))
  }

  /// Reads JSON text; `nil` when it is not JSON.
  public init?(parsing text: String) {
    guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else { return nil }
    self = value
  }

  public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
    try JSONDecoder().decode(type, from: data())
  }

  /// Compact, keys sorted, so the same value is always the same bytes.
  public func data() throws -> Data {
    try Self.encoder.encode(self)
  }

  /// `data()` as text; `null` for a value that cannot be written, which none can.
  public var text: String {
    (try? data()).map { String(decoding: $0, as: UTF8.self) } ?? "null"
  }

  private static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}

extension JSONValue: Codable {
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
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
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
    case .array(let values): try container.encode(values)
    case .object(let members): try container.encode(members)
    }
  }
}
