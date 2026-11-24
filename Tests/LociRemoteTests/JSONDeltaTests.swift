import Foundation
import LociModel
import Testing

@testable import LociRemote

struct JSONDeltaTests {
  static let pairs: [(JSONValue, JSONValue)] = [
    (.object(["a": .integer(1), "b": .string("x")]), .object(["a": .integer(2), "c": .bool(true)])),
    (.array([.integer(1), .integer(2)]), .array([.integer(1), .integer(3), .integer(4)])),
    (.array([.integer(1), .integer(2), .integer(3)]), .array([.integer(1)])),
    (.string("Hello"), .string("Hello, world")),
    (.string("Hello"), .string("Goodbye")),
    (.integer(1), .string("one")),
    (
      .object(["list": .array([.object(["text": .string("a")])])]),
      .object(["list": .array([.object(["text": .string("ab")])])])
    ),
    (.null, .number(1.5)),
  ]

  @Test func applyingTheDeltaGivesTheNewValue() throws {
    for (old, new) in Self.pairs {
      let delta = try #require(JSONDelta.from(old, to: new))
      #expect(try delta.apply(to: old) == new)
    }
    #expect(JSONDelta.from(.integer(1), to: .integer(1)) == nil)
  }

  @Test func aGrowingReplySendsOnlyTheNewWords() throws {
    let words = (0..<500).map { "word\($0)" }.joined(separator: " ")
    let old = try JSONValue(encoding: ["messages": [["text": words]]])
    let new = try JSONValue(encoding: ["messages": [["text": words + " and more"]]])

    let delta = try #require(JSONDelta.from(old, to: new))
    let sent = try JSONEncoder().encode(delta)

    #expect(sent.count < 200)
    #expect(try delta.apply(to: old) == new)
  }

  @Test func aDeltaForAnotherValueIsRefused() {
    let delta = JSONDelta.array(kept: 5, changed: [:], appended: [])

    #expect(throws: DeltaMismatch.self) { try delta.apply(to: .array([.integer(1)])) }
    #expect(throws: DeltaMismatch.self) { try JSONDelta.appendText("x").apply(to: .integer(1)) }
  }

  @Test func encodableValuesRoundTripThroughTheTree() throws {
    struct Value: Codable, Equatable {
      let id: Int64
      let ratio: Double
      let name: String
      let tags: [String]
      let missing: String?
    }
    let value = Value(id: 1_763_337_600_123, ratio: 0.25, name: "调度", tags: ["a"], missing: nil)

    #expect(try JSONValue(encoding: value).decode(Value.self) == value)
  }
}
