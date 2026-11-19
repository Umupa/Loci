import Foundation
import LociModel
import Testing

@testable import LociUI

struct RowRunTests {
  private static func message(_ second: Int64, _ body: Message.Body) -> Message {
    Message(id: EntityID(), at: Timestamp(millisecondsSince1970: second * 1000), body: body)
  }

  private static func asked(_ second: Int64) -> Message {
    message(second, .prompt(Prompt(text: "问", purpose: .chat)))
  }

  private static func said(_ questions: Int) -> [Message] {
    (0..<questions).flatMap { [Self.asked(Int64($0) * 10), Self.message(Int64($0) * 10 + 1, .reply("好。\n\n嗯。"))] }
  }

  @Test func olderRowsAreDrawnInRunsAndTheRecentOnesOneByOne() {
    let rows = TalkRow.rows(ConversationEntry.layout(Self.said(60).map { .message($0) }, live: false), waiting: false)
    let (runs, recent) = RowRun.split(rows)

    #expect(runs.flatMap { $0.rows.map(\.id) } + recent.map(\.id) == rows.map(\.id))
    #expect(runs.allSatisfy { $0.rows.count == RowRun.length })
    #expect(recent.count >= RowRun.recent && recent.count < RowRun.recent + RowRun.length)
  }

  @Test func theAnswerJustWrittenStaysOneByOneWhenItsTurnEnds() {
    let said = Self.said(60)
    let asked = Self.asked(5000)
    let answer = Self.message(5001, .reply((1...20).map { "第 \($0) 段。" }.joined(separator: "\n\n")))
    let ended = TalkRow.settled(SaidSoFar((said + [asked, answer]).map { .message($0) }, turn: nil))

    let answerRows = Set(ended.filter { $0.id.message == answer.id }.map(\.id))
    #expect(answerRows.count == 20)
    #expect(answerRows.isSubset(of: Set(RowRun.split(ended).recent.map(\.id))))
  }
}
