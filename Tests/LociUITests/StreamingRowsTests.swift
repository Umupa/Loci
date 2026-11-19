import Foundation
import LociModel
import Testing

@testable import LociUI

@MainActor
struct StreamingRowsTests {
  private static func message(_ second: Int64, _ body: Message.Body) -> Message {
    Message(id: EntityID(), at: Timestamp(millisecondsSince1970: second * 1000), body: body)
  }

  private static let read = ToolActivity(
    id: "r", name: "read", kind: .read, subject: "a.md", output: "", state: .succeeded)

  private static func summary(_ rows: [TalkRow]) -> [String] {
    rows.map { row in
      let kind =
        switch row.kind {
        case .day: "day"
        case .asked(let prompt): "asked " + prompt.text
        case .said(let words, let answer): "said \(words) \(answer ?? "-")"
        case .typing: "typing"
        case .steps(let steps): "steps \(steps.map { $0.took.map { "\($0)" } ?? "going" })"
        case .aside: "aside"
        case .saved: "saved"
        case .finished(let item, _): "finished " + item.title
        case .task(let item, _): "task " + item.title
        case .cards(let items): "cards \(items.count)"
        }
      return
        "\(row.id.message.map { "\($0)" } ?? "-")/\(row.id.part) \(kind) \(row.position.map { "\($0)" } ?? "-") \(row.turn)"
    }
  }

  private static func whole(_ said: [Message], turn: [Message]) -> [TalkRow] {
    let waiting = if case .prompt = turn.last?.body { true } else { false }
    return TalkRow.rows(
      ConversationEntry.layout((said + turn).map { .message($0) }, live: !turn.isEmpty), waiting: waiting)
  }

  private static func split(_ said: [Message], turn: [Message]) -> [TalkRow] {
    let live = turn.isEmpty ? nil : LiveTurn(startedAt: turn[0].at, messages: turn)
    return TalkRow.settled(SaidSoFar(said.map { .message($0) }, turn: live)) + TalkRow.live(live)
  }

  @Test func aRunningTurnIsDrawnTheSameWhetherOrNotWhatWasSaidBeforeItIsLaidOutAgain() {
    let said = [
      Self.message(0, .prompt(Prompt(text: "一", purpose: .chat))), Self.message(1, .reply("好\n\n再说")),
      Self.message(2, .tool(Self.read)),
    ]
    let asked = Self.message(9000, .prompt(Prompt(text: "二", purpose: .chat)))
    let turns: [[Message]] = [
      [],
      [asked],
      [asked, Self.message(9001, .thinking("想"))],
      [asked, Self.message(9001, .reply("先说结论。\n\n不划算。")), Self.message(9003, .tool(Self.read))],
      [
        asked, Self.message(9001, .reply("先说")), Self.message(9002, .tool(Self.read)),
        Self.message(9004, .reply("嗯。\n\n因为")),
      ],
      [asked, Self.message(13000, .reply("隔了一小时。"))],
    ]

    for turn in turns {
      #expect(Self.summary(Self.split(said, turn: turn)) == Self.summary(Self.whole(said, turn: turn)))
    }
  }

  @Test func whatWasSaidIsLaidOutAgainOnlyWhenItChangesNotAsAReplyStreams() {
    var laidOut = 0
    let settled = Remembered { (said: SaidSoFar) -> [TalkRow] in
      laidOut += 1
      return TalkRow.settled(said)
    }
    let history: [Conversation.Entry] = [.message(Self.message(0, .prompt(Prompt(text: "一", purpose: .chat))))]
    let asked = Self.message(10, .prompt(Prompt(text: "二", purpose: .chat)))
    let reply = Self.message(11, .reply("先"))

    _ = settled(SaidSoFar(history, turn: LiveTurn(startedAt: asked.at, messages: [asked])))
    for words in ["先说", "先说结论", "先说结论。"] {
      let growing = Message(id: reply.id, at: reply.at, body: .reply(words))
      _ = settled(SaidSoFar(history, turn: LiveTurn(startedAt: asked.at, messages: [asked, growing])))
    }
    #expect(laidOut == 1)

    _ = settled(SaidSoFar(history + [.message(asked), .message(reply)], turn: nil))
    #expect(laidOut == 2)
  }

  @Test func onlyTheFirstBubbleOfAMessageArrives() {
    let asked = Self.message(0, .prompt(Prompt(text: "问", purpose: .chat)))
    let id = EntityID()
    func arrivals(_ reply: String?) -> Int {
      let answer = reply.map { [Message(id: id, at: asked.at, body: .reply($0))] } ?? []
      return TalkRow.live(LiveTurn(startedAt: asked.at, messages: [asked] + answer)).count(where: \.arrives)
    }

    #expect(arrivals(nil) == 1)
    #expect(arrivals("一。") == 1)
    #expect(arrivals("一。\n\n二。\n\n三。") == 1)
  }
}
