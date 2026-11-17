import Foundation
import Testing

@testable import LociModel

struct EntityIDTests {
  @Test func laterIdentifiersSortAfterEarlierOnes() {
    var entropy = SeededGenerator(seed: 1)
    let earlier = EntityID(at: Date(timeIntervalSince1970: 1_000), entropy: &entropy)
    let later = EntityID(at: Date(timeIntervalSince1970: 1_000.001), entropy: &entropy)

    #expect(earlier < later)
    #expect(earlier.description < later.description)
  }

  @Test func remembersWhenItWasCreated() {
    var entropy = SeededGenerator(seed: 2)
    let instant = Date(timeIntervalSince1970: 1_763_337_600.123)

    let id = EntityID(at: instant, entropy: &entropy)

    #expect(abs(id.createdAt.timeIntervalSince(instant)) < 0.001)
  }

  @Test func textFormRoundTrips() throws {
    let id = EntityID()

    #expect(EntityID(id.description) == id)
    #expect(id.description == id.description.lowercased())

    let decoded = try JSONDecoder().decode(EntityID.self, from: JSONEncoder().encode(id))
    #expect(decoded == id)
  }

  @Test(arguments: ["", "not-an-id", "3f2b8c1e-9d4a-4b6f-8a1c-2e5d7f9b0c3a"])
  func rejectsAnythingButVersionSeven(text: String) {
    #expect(EntityID(text) == nil)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(EntityID.self, from: JSONEncoder().encode(text))
    }
  }

  @Test func canonicalParsingAcceptsOnlyTheLowercaseForm() {
    let id = EntityID()

    #expect(EntityID(canonical: id.description) == id)
    #expect(EntityID(canonical: id.description.uppercased()) == nil)
    #expect(EntityID(id.description.uppercased()) == id)
  }

  @Test func sameInstantStillYieldsDistinctIdentifiers() {
    var entropy = SeededGenerator(seed: 3)
    let instant = Date(timeIntervalSince1970: 1_000)

    let ids = Set((0..<1_000).map { _ in EntityID(at: instant, entropy: &entropy) })

    #expect(ids.count == 1_000)
  }
}

struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}
