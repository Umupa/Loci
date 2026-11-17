import AppKit
import LociModel
import Testing

@testable import LociUI

struct PlacedNoteTests {
  static let lesson = LessonRef(mentor: EntityID(), lesson: Lesson.Slug("filter")!)

  static func note(_ quote: String, thought: String? = nil) throws -> Note {
    try Note(
      id: EntityID(), locator: .lesson(lesson, try TextQuote(quote)), excerpt: quote, thought: thought,
      savedAt: Timestamp(millisecondsSince1970: 0))
  }

  @Test func notesFollowTheTextAndLostOnesComeLast() throws {
    let text = ReadingText(markdown: "# 过滤\n\n先排除不合适的节点。\n\n再给节点**打分**。")
    let later = try Self.note("打分")
    let lost = try Self.note("抢占")
    let earlier = try Self.note("不合适")

    let placed = PlacedNote.place([later, lost, earlier], in: text)

    #expect(placed.map(\.id) == [earlier.id, later.id, lost.id])
    #expect(placed.last?.range == nil)
    #expect(placed.first.flatMap(\.range).map { (text.plain as NSString).substring(with: $0) } == "不合适")
  }

  @Test func onlyNotesWithMoreThanAHighlightGetAMarginMark() throws {
    let text = ReadingText(markdown: "先排除不合适的节点，再给节点打分。")
    let plain = try Self.note("不合适")
    let thought = try Self.note("打分", thought: "为什么要分两步？")
    let asked = try Self.note("节点，")

    let marks = PlacedNote.marks(PlacedNote.place([plain, thought, asked], in: text), pending: [asked.id])

    #expect(
      marks.map(\.kind) == [
        .note(plain.id, marginMark: false), .note(asked.id, marginMark: true), .note(thought.id, marginMark: true),
      ])
  }
}
