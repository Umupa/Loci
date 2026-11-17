import Foundation
import Testing

@testable import LociModel

struct MentorTests {
  static func json(provider: String = "claude-code", color: String = "#C0FFEE", name: String = "调度") -> String {
    """
    {"id":"\(Fixture.mentor)","name":"\(name)","avatar":"owl","color":"\(color)",
     "provider":"\(provider)","permission":"full"}
    """
  }

  @Test func readsMentorJSONAndWritesItBack() throws {
    let mentor = try Fixture.decode(Mentor.self, Self.json())

    #expect(mentor.name == "调度")
    #expect(mentor.provider == .claudeCode)
    #expect(mentor.model == nil)
    #expect(mentor.color == MentorColor(red: 0xC0, green: 0xFF, blue: 0xEE))
    #expect(try Fixture.roundTrip(mentor) == mentor)
  }

  /// Mentors from before every mentor ran with full access still load; the old choice is dropped.
  @Test func aMentorFileWithAPermissionStillReads() throws {
    let mentor = try Fixture.decode(Mentor.self, Self.json())
    let written = String(decoding: try JSONEncoder().encode(mentor), as: UTF8.self)

    #expect(!written.contains("permission"))
  }

  @Test func theThinkingEffortIsKeptWhenGiven() throws {
    let json = Self.json().replacing(#""permission":"full""#, with: #""effort":"high""#)
    let mentor = try Fixture.decode(Mentor.self, json)

    #expect(mentor.effort == .high)
    #expect(try Fixture.roundTrip(mentor) == mentor)
  }

  @Test func onlySomeAgentsOfferThinkingEfforts() {
    #expect(Mentor.Provider.claudeCode.efforts == [.low, .medium, .high, .xhigh, .max])
    #expect(Mentor.Provider.codex.efforts == [.low, .medium, .high, .xhigh, .max])
    #expect(Mentor.Provider.pi.efforts == [.off, .minimal, .low, .medium, .high, .xhigh, .max])
    #expect(Mentor.Provider.grok.efforts.isEmpty)
  }

  @Test func colorIsWrittenInLowercase() {
    #expect(MentorColor("#C0FFEE")?.description == "#c0ffee")
    #expect(MentorColor(red: 1, green: 2, blue: 3).description == "#010203")
  }

  @Test(arguments: ["c0ffee", "#c0ffe", "#c0ffee0", "#g0ffee", "#+0ffee"])
  func rejectsColorsThatAreNotSixHexDigits(text: String) {
    #expect(MentorColor(text) == nil)
  }

  @Test func everyProviderHasAStableName() throws {
    for provider in Mentor.Provider.allCases {
      #expect(try Fixture.decode(Mentor.self, Self.json(provider: provider.rawValue)).provider == provider)
    }
  }

  @Test(arguments: [json(provider: "claude"), json(color: "red"), json(name: "  ")])
  func aMentorFileWithAnUnknownOrBrokenFieldDoesNotLoad(json: String) {
    #expect(throws: DecodingError.self) { try Fixture.decode(Mentor.self, json) }
  }

  @Test func blankFieldsAreRefused() {
    let color = MentorColor(red: 0, green: 0, blue: 0)
    #expect(throws: ModelError.self) {
      try Mentor(id: Fixture.mentor, name: "x", avatar: "", color: color, provider: .pi)
    }
    #expect(throws: ModelError.self) {
      try Mentor(id: Fixture.mentor, name: "x", avatar: "owl", color: color, provider: .pi, model: "")
    }
  }
}
