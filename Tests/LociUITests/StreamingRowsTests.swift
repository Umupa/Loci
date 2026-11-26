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

  /// A moment long after anything here began, when every reply being written shows.
  private static let shown = ReplyHold(now: .distantFuture, wait: .seconds(1))

  private static func summary(_ rows: [TalkRow]) -> [String] {
    rows.map { row in
      let kind =
        switch row.kind {
        case .day: "day"
        case .asked(let prompt): "asked " + prompt.text
        case .said(let words, let answer): "said \(words) \(answer ?? "-")"
        case .doing(let doing): "doing \(doing)"
        case .ended: "ended"
        case .startedOver: "startedOver"
        case .saved: "saved"
        case .savedItems(let ids): "saved items \(ids.count)"
        case .document(let document): "document " + (document.title ?? "-")
        case .links(let links): "links \(links.count)"
        }
      return "\(row.id.message.map { "\($0)" } ?? "-")/\(row.id.part) \(kind)"
    }
  }

  private static func whole(_ said: [Message], turn: [Message]) -> [TalkRow] {
    let live = turn.isEmpty ? nil : LiveTurn(startedAt: turn[0].at, messages: turn)
    return TalkRow.rows(ConversationEntry.layout((said + turn).map { .message($0) }, live: live != nil), turn: live)
  }

  private static func split(_ said: [Message], turn: [Message]) -> [TalkRow] {
    let live = turn.isEmpty ? nil : LiveTurn(startedAt: turn[0].at, messages: turn)
    return TalkRow.settled(SaidSoFar(said.map { .message($0) }, turn: live)) + TalkRow.live(live, hold: Self.shown)
  }

  @Test func aRunningTurnIsLaidOutAgainOnlyWhenItChangesOrItsHeldReplyComesDue() {
    var made = 0
    let live = Remembered { (said: LiveSoFar) -> [TalkRow] in
      made += 1
      return TalkRow.live(said)
    }
    let asked = Self.message(0, .prompt(Prompt(text: "问", purpose: .chat)))
    let turn = LiveTurn(
      startedAt: asked.at, messages: [asked, Self.message(1, .tool(Self.read)), Self.message(2, .reply("结论。"))])
    func at(_ second: TimeInterval, _ turn: LiveTurn) -> LiveSoFar {
      LiveSoFar(turn, hold: ReplyHold(now: Date(timeIntervalSince1970: second), wait: .seconds(1)))
    }

    _ = live(at(2, turn))
    _ = live(at(2.5, turn))
    #expect(made == 1)
    #expect(Self.summary(live(at(3, turn))).last?.hasSuffix("said 结论。 -") == true)
    _ = live(at(4, turn))
    #expect(made == 2)
    let longer = LiveTurn(
      startedAt: turn.startedAt,
      messages: Array(turn.messages.dropLast()) + [
        Message(id: turn.messages[2].id, at: turn.messages[2].at, body: .reply("结论。再说"))
      ])
    _ = live(at(4, longer))
    #expect(made == 3)
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
      return TalkRow.live(LiveTurn(startedAt: asked.at, messages: [asked] + answer), hold: Self.shown).count(
        where: \.arrives)
    }

    #expect(arrivals(nil) == 1)
    #expect(arrivals("一。") == 1)
    #expect(arrivals("一。\n\n二。\n\n三。") == 1)
  }
}
