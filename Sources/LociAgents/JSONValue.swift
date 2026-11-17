import Foundation

/// Any JSON value: tool arguments and provider records whose shape the drivers do not fix.
public enum JSONValue: Hashable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members[key]
  }

  public var string: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  public var bool: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }

  public var int: Int? {
    guard case .number(let value) = self, let exact = Int(exactly: value.rounded()) else { return nil }
    return exact
  }

  public var array: [JSONValue]? {
    guard case .array(let values) = self else { return nil }
    return values
  }
}

extension JSONValue {
  /// The value as one line of JSON Lines: keys sorted, ending in a line feed.
  var line: Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = (try? encoder.encode(self)) ?? Data()
    data.append(0x0A)
    return data
  }
}

extension JSONValue: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
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
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let values): try container.encode(values)
    case .object(let members): try container.encode(members)
    }
  }
}
