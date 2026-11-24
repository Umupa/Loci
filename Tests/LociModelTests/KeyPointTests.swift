import Foundation
import LociModel
import Testing

/// K-S4, K-S7: key points are their own kind of thing, apart from the reader's highlights.
struct KeyPointTests {
  static func stretch(_ start: Int, _ end: Int) throws -> KeyPoint {
    try KeyPoint(place: .time(try TimeSpan(start: .seconds(start), end: .seconds(end))), title: "T", reason: "R")
  }

  static func passage(_ number: Int) throws -> KeyPoint {
    try KeyPoint(place: .passage(try .init(number: number, text: "Paragraph \(number).")), title: "T", reason: "R")
  }

  @Test func keyPointsKeepTheirOrderAndRefuseOverlaps() throws {
    let points = try KeyPoints(points: [try Self.stretch(0, 10), try Self.stretch(10, 20)], choice: .standard)
    #expect(points.points.count == 2)
    #expect(throws: ModelError.self) {
      try KeyPoints(points: [try Self.stretch(0, 10), try Self.stretch(5, 20)], choice: .standard)
    }
    #expect(throws: ModelError.self) {
      try KeyPoints(points: [try Self.stretch(20, 30), try Self.stretch(0, 10)], choice: .standard)
    }
  }

  @Test func keyPointsAreAllTimesOrAllPassages() throws {
    #expect(throws: ModelError.self) {
      try KeyPoints(points: [try Self.stretch(0, 10), try Self.passage(3)], choice: .standard)
    }
    #expect(throws: ModelError.self) { try KeyPoints(points: [], choice: .standard) }
    #expect(throws: ModelError.self) {
      try KeyPoints(points: [try Self.passage(4), try Self.passage(2)], choice: .standard)
    }
  }

  @Test func aKeyPointInTimeHasAnEnd() {
    #expect(throws: ModelError.self) {
      try KeyPoint(place: .time(try TimeSpan(start: .seconds(1))), title: "T", reason: "R")
    }
  }

  @Test func keyPointsSurviveTheirFile() throws {
    let media = try KeyPoints(
      points: [try Self.stretch(1, 9)],
      choice: KeyPointChoice(model: ModelChoice(provider: ModelProviderID(.kimi), model: "kimi-k3"), count: .many))
    let article = try KeyPoints(points: [try Self.passage(2), try Self.passage(7)], choice: .standard)

    #expect(try Fixture.roundTrip(media) == media)
    #expect(try Fixture.roundTrip(article) == article)
  }

  @Test func eachCountAllowsItsRange() {
    #expect(KeyPointCount.allCases.map(\.range) == [3...4, 4...6, 6...8])
    #expect(KeyPointChoice.standard.count == .some)
    #expect(KeyPointChoice.standard.model == nil)
  }

  @Test func anOutlineFileWithTheOldHighlightsStillReadsItsChapters() throws {
    let file =
      #"{"chapters": [{"start": 0, "title": "Intro"}], "highlights": [{"start": 1, "end": 2, "title": "T", "reason": "R"}]}"#

    let outline = try JSONDecoder().decode(Outline.self, from: Data(file.utf8))

    #expect(outline.chapters.map(\.title) == ["Intro"])
  }
}
