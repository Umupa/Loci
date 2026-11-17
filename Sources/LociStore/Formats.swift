import Foundation
import Yams

enum Formats {
  static func document(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value) + Data("\n".utf8)
  }

  static func line(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value) + Data("\n".utf8)
  }

  static func yaml(_ value: some Encodable) throws -> String {
    let encoder = YAMLEncoder()
    encoder.options.allowUnicode = true
    return try encoder.encode(value)
  }

  static func fromYAML<Value: Decodable>(_ type: Value.Type, _ text: String) throws -> Value {
    let isBlank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return try YAMLDecoder().decode(type, from: isBlank ? "{}" : text)
  }

  /// One line saying which field is wrong and why.
  static func reason(_ error: any Error) -> String {
    switch error {
    case DecodingError.dataCorrupted(let context):
      describe(context, context.underlyingError.map { "\(context.debugDescription) \($0)" } ?? context.debugDescription)
    case DecodingError.keyNotFound(let key, let context):
      "\(path(context.codingPath + [key])): missing"
    case DecodingError.typeMismatch(let type, let context):
      describe(context, "expected \(type)")
    case DecodingError.valueNotFound(let type, let context):
      describe(context, "expected \(type), found nothing")
    default:
      String(describing: error)
    }
  }

  private static func describe(_ context: DecodingError.Context, _ message: String) -> String {
    context.codingPath.isEmpty ? message : "\(path(context.codingPath)): \(message)"
  }

  private static func path(_ keys: [any CodingKey]) -> String {
    keys.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
  }
}
