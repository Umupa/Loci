import Foundation

@testable import LociModel

enum Fixture {
  static func id(_ seed: UInt64) -> EntityID {
    var entropy = SeededGenerator(seed: seed)
    return EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + Double(seed)), entropy: &entropy)
  }

  static let item = id(1)
  static let mentor = id(2)
  static let commit = CommitID(String(repeating: "ab12", count: 10))!
  static let instant = Timestamp(millisecondsSince1970: 1_763_337_600_123)

  static func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
    try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
  }

  static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(json.utf8))
  }
}
