import AppKit
import LociModel
import Testing

@testable import LociUI

@MainActor
struct PlacedNoteTests {
  static let item = EntityID()

  static func note(_ quote: String, thought: String? = nil) throws -> Note {
    try Note(
      id: EntityID(), locator: .item(item, .quote(try TextQuote(quote))), excerpt: quote, thought: thought,
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

  /// HL-S5: a highlight with a thought is underlined in amber; one with questions also gets a dot.
  @Test func highlightsWithAThoughtAreUnderlinedAndOnesWithQuestionsGetADot() throws {
    let text = ReadingText(markdown: "先排除不合适的节点，再给节点打分，最后绑定。")
    let plain = try Self.note("不合适")
    let thought = try Self.note("打分", thought: "为什么要分两步？")
    let exchange = try Note.Exchange(question: "为什么？", answer: "因为……", askedAt: Timestamp(millisecondsSince1970: 0))
    let asked = try Note(
      id: EntityID(), locator: .item(Self.item, .quote(try TextQuote("绑定"))), excerpt: "绑定", exchanges: [exchange],
      savedAt: Timestamp(millisecondsSince1970: 0))

    let marks = PlacedNote.marks(PlacedNote.place([plain, thought, asked], in: text))

    #expect(marks.map(\.note) == [plain.id, thought.id, asked.id])
    #expect(marks.map(\.thought) == [nil, "为什么要分两步？", nil])
    #expect(marks.map(\.marginMark) == [false, false, true])
  }

  /// HL-S6: the thought on the whole item is not a place in the text.
  @Test func theThoughtOnTheWholeItemIsNotAmongTheHighlights() throws {
    let text = ReadingText(markdown: "先排除不合适的节点。")
    let whole = try Note(
      id: EntityID(), locator: .item(Self.item, .whole), thought: "两步走", savedAt: Timestamp(millisecondsSince1970: 0))
    let plain = try Self.note("不合适")

    let placed = PlacedNote.place([whole, plain], in: text)

    #expect(placed.map(\.id) == [plain.id])
  }
}
