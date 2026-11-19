import Foundation
import LociModel
import Testing

@testable import LociUI

struct RowWindowTests {
  private static func rows(_ questions: Int) -> [TalkRow] {
    let said = (0..<questions).flatMap { question in
      [
        Message(
          id: EntityID(), at: Timestamp(millisecondsSince1970: Int64(question) * 10_000),
          body: .prompt(Prompt(text: "问 \(question)", purpose: .chat))),
        Message(
          id: EntityID(), at: Timestamp(millisecondsSince1970: Int64(question) * 10_000 + 1000),
          body: .reply("一。\n\n二。\n\n三。")),
      ]
    }
    return TalkRow.rows(ConversationEntry.layout(said.map { .message($0) }, live: false), waiting: false)
  }

  @Test func aShortConversationIsDrawnWhole() {
    let rows = Self.rows(20)

    #expect(RowWindow.latest(in: rows) == 0)
  }

  @Test func aLongConversationIsDrawnFromAQuestionNotLongBeforeItsEnd() {
    let rows = Self.rows(1000)
    let start = RowWindow.latest(in: rows)

    #expect(rows.count - start >= RowWindow.length)
    #expect(rows.count - start < RowWindow.length + 8)
    #expect(rows[start].arrives)
  }

  @Test func reachingTheTopDrawsAnEarlierStretchUntilTheFirstMessage() {
    let rows = Self.rows(1000)
    var start = RowWindow.latest(in: rows)
    var stretches = 0
    while start > 0 && stretches < 100 {
      let earlier = RowWindow.earlier(than: start, in: rows)
      #expect(earlier == 0 || start - earlier >= RowWindow.step)
      #expect(rows[earlier].arrives)
      start = earlier
      stretches += 1
    }

    #expect(start == 0)
  }
}
