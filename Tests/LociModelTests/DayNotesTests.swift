import Testing

@testable import LociModel

struct DayNotesTests {
  static let day = Day("2026-11-18")!

  static func notes(_ text: String) -> [Line<DayNote>] {
    DayNotes(day: day, parsing: text, title: { $0 == Fixture.item ? "Pingora" : nil }).notes
  }

  @Test func aNoteHasATimeAPlaceAndWords() {
    #expect(
      Self.notes(
        "# 2026-11-18\n\n- 00:31 [main] 读完 Pingora。\n- 9:12 [library/\(Fixture.item)] 图画好了\n- 23:20 [review] 回顾") == [
          .entry(DayNote(time: TimeOfDay("00:31"), text: "读完 Pingora。", from: .main)),
          .entry(DayNote(time: TimeOfDay("09:12"), text: "图画好了", from: .item(Fixture.item, title: "Pingora"))),
          .entry(DayNote(time: TimeOfDay("23:20"), text: "回顾", from: .review)),
        ])
  }

  @Test func theTimeAndThePlaceMayBeLeftOut() {
    #expect(
      Self.notes("- [main] 没写时间\n- 10:00 没写来源\n- 只有字") == [
        .entry(DayNote(time: nil, text: "没写时间", from: .main)),
        .entry(DayNote(time: TimeOfDay("10:00"), text: "没写来源", from: nil)),
        .entry(DayNote(time: nil, text: "只有字", from: nil)),
      ])
  }

  @Test func anUnknownPlaceStaysInTheWords() {
    #expect(
      Self.notes("- 10:00 [later] 想法") == [.entry(DayNote(time: TimeOfDay("10:00"), text: "[later] 想法", from: nil))])
  }

  @Test func aNoteWithoutWordsAndOtherLinesShowAsWritten() {
    #expect(Self.notes("- 10:00 [main]\nsome prose") == [.text("- 10:00 [main]"), .text("some prose")])
  }

  @Test func everyPlaceWritesTheTagItIsReadBackFrom() {
    for source in [NoteSource.main, .review, .item(Fixture.item, title: "Pingora")] {
      #expect(NoteSource(tag: source.tag, title: { _ in "Pingora" }) == source)
    }
  }
}
