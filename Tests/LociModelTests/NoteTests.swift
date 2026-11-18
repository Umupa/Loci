import Foundation
import Testing

@testable import LociModel

struct NoteTests {
  static let locator = Locator("loci://library/\(Fixture.item)#quote=过滤")!

  static func note(_ seed: UInt64, thought: String? = nil, at offset: Int64 = 0) throws -> Note {
    try Note(
      id: Fixture.id(seed), locator: locator, thought: thought,
      savedAt: Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + offset))
  }

  @Test func aSavedNoteSurvivesOneLineOfJSON() throws {
    let exchange = try Note.Exchange(question: "为什么?", answer: "因为……", askedAt: Fixture.instant)
    let note = try Note(
      id: Fixture.id(5), locator: Self.locator, excerpt: "过滤", thought: "像漏斗", exchanges: [exchange],
      savedAt: Fixture.instant)
    let line = String(decoding: try JSONEncoder().encode(NoteEntry.saved(note)), as: UTF8.self)

    #expect(!line.contains("\n"))
    #expect(line.contains(#""savedAt":"2025-11-17T00:00:00.123Z""#))
    #expect(try Fixture.roundTrip(NoteEntry.saved(note)) == .saved(note))
  }

  @Test func anExchangeSavedByAnEarlierVersionStillReads() throws {
    let line =
      #"{"event":"saved","id":"\#(Fixture.id(5))","locator":"\#(Self.locator)","savedAt":"2025-11-17T00:00:00.123Z","exchanges":[{"question":"q","answer":"a","mentor":"\#(Fixture.id(2))","askedAt":"2025-11-17T00:00:00.123Z"}]}"#

    guard case .saved(let note) = try Fixture.decode(NoteEntry.self, line) else { throw ModelError("not saved") }
    #expect(note.exchanges == [try Note.Exchange(question: "q", answer: "a", askedAt: Fixture.instant)])
  }

  @Test func aDeletionSurvivesJSON() throws {
    let entry = NoteEntry.deleted(Fixture.id(5), at: Fixture.instant)

    #expect(try Fixture.roundTrip(entry) == entry)
  }

  @Test func aPlainHighlightIsANote() throws {
    let note = try Fixture.decode(
      NoteEntry.self,
      #"{"event":"saved","id":"\#(Fixture.id(5))","locator":"\#(Self.locator)","savedAt":"2025-11-17T00:00:00.123Z"}"#)

    #expect(note == .saved(try Note(id: Fixture.id(5), locator: Self.locator, savedAt: Fixture.instant)))
  }

  static let broken = [
    #"{"event":"edited","id":"\#(Fixture.id(5))","at":"2025-11-17T00:00:00.123Z"}"#,
    #"{"event":"saved","id":"\#(Fixture.id(5))","locator":"loci://nowhere","savedAt":"2025-11-17T00:00:00.123Z"}"#,
    #"{"event":"saved","id":"\#(Fixture.id(5))","locator":"\#(locator)","savedAt":1763337600}"#,
    #"{"event":"saved","id":"\#(Fixture.id(5))","locator":"\#(locator)","thought":"","savedAt":"2025-11-17T00:00:00.123Z"}"#,
    #"{"event":"saved","id":"\#(Fixture.id(5))","locator":"\#(locator)","savedAt":"2025-11-17T00:00:00.123Z","exchanges":[{"question":"q","answer":"","askedAt":"2025-11-17T00:00:00.123Z"}]}"#,
  ]

  @Test(arguments: broken)
  func aBrokenLineIsRejected(line: String) {
    #expect(throws: DecodingError.self) { try Fixture.decode(NoteEntry.self, line) }
  }

  @Test func anEditedNoteShowsOnlyItsLatestVersionInItsOriginalPlace() throws {
    let entries: [NoteEntry] = [
      .saved(try Self.note(1)), .saved(try Self.note(2)), .saved(try Self.note(1, thought: "改过", at: 5)),
    ]

    #expect(Note.current(in: entries) == [try Self.note(1, thought: "改过", at: 5), try Self.note(2)])
  }

  @Test func aDeletedNoteIsGoneForGood() throws {
    let entries: [NoteEntry] = [
      .saved(try Self.note(1)), .saved(try Self.note(2)), .deleted(Fixture.id(1), at: Fixture.instant),
      .saved(try Self.note(1, thought: "复活?", at: 9)),
    ]

    #expect(Note.current(in: entries) == [try Self.note(2)])
  }
}
