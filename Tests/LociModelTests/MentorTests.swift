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
      try Mentor(id: Fixture.mentor, name: "x", avatar: "", color: color, provider: .pi, permission: .ask)
    }
    #expect(throws: ModelError.self) {
      try Mentor(id: Fixture.mentor, name: "x", avatar: "owl", color: color, provider: .pi, model: "", permission: .ask)
    }
  }
}
