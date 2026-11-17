import Foundation
import Testing

@testable import LociModel

struct TimestampTests {
  @Test func writesUTCWithMilliseconds() {
    #expect(Fixture.instant.description == "2025-11-17T00:00:00.123Z")
    #expect(Timestamp(millisecondsSince1970: 0).description == "1970-01-01T00:00:00.000Z")
    #expect(Timestamp(millisecondsSince1970: -1).description == "1969-12-31T23:59:59.999Z")
  }

  @Test(arguments: [0, -1, 1_763_337_600_123, 1_763_337_600_999, 4_102_444_800_001] as [Int64])
  func survivesTextAndJSON(milliseconds: Int64) throws {
    let timestamp = Timestamp(millisecondsSince1970: milliseconds)

    #expect(Timestamp(timestamp.description) == timestamp)
    #expect(try Fixture.roundTrip(timestamp) == timestamp)
  }

  @Test func aDateIsRoundedToTheNearestMillisecond() {
    #expect(Timestamp(Date(timeIntervalSince1970: 1.0006)) == Timestamp(millisecondsSince1970: 1_001))
    #expect(Timestamp(Fixture.instant.date) == Fixture.instant)
  }

  @Test(arguments: ["2025-11-17T00:00:00Z", "2025-11-17T00:00:00.12Z", "2025-11-17T08:00:00.123+08:00", "1763337600"])
  func rejectsAnyOtherForm(text: String) {
    #expect(Timestamp(text) == nil)
  }
}
