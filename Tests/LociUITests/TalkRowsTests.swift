import Foundation
import LociModel
import Testing

@testable import LociUI

struct TalkRowsTests {
  private static func message(_ second: Int64, _ body: Message.Body) -> Message {
    Message(id: EntityID(), at: Timestamp(millisecondsSince1970: second * 1000), body: body)
  }

  private static func asked(_ second: Int64, _ text: String) -> Message {
    message(second, .prompt(Prompt(text: text, purpose: .chat)))
  }

  private static func rows(_ messages: [Message], live: Bool = false) -> [TalkRow] {
    TalkRow.rows(ConversationEntry.layout(messages.map { .message($0) }, live: live), waiting: false)
  }

  private static func kinds(_ rows: [TalkRow]) -> [String] {
    rows.map { row in
      switch row.kind {
      case .day: "day"
      case .asked(let prompt): "asked " + prompt.text
      case .said(let words, _): "said " + words
      case .typing: "typing"
      case .steps: "steps"
      case .aside: "aside"
      case .saved: "saved"
      case .finished(let item, _): "finished " + item.title
      case .task(let item, _): "task " + item.title
      case .cards(let items): "cards " + items.map(\.title).joined(separator: " ")
      case .savedItems(let items): "savedItems \(items.count)"
      }
    }
  }

  @Test func aReplyArrivesAsOneBubbleForEachParagraphUnderTheQuestion() {
    let rows = Self.rows([Self.asked(0, "看到哪了"), Self.message(1, .reply("都快十二点了\n\n看到哪了"))])

    #expect(Self.kinds(rows) == ["day", "asked 看到哪了", "said 都快十二点了", "said 看到哪了"])
    #expect(rows.map(\.position) == [nil, .alone, .first, .last])
    #expect(rows.map(\.turn) == [false, false, true, false])
  }

  @Test func aNewSittingAfterAnHourIsHeadedByItsTime() {
    let rows = Self.rows([Self.asked(0, "一"), Self.message(1, .reply("嗯")), Self.asked(4000, "二")])

    #expect(Self.kinds(rows) == ["day", "asked 一", "said 嗯", "day", "asked 二"])
  }

  @Test func onlyTheLastPartOfAFinishedAnswerCarriesItForCopying() {
    let reply = Self.message(1, .reply("一\n\n二"))
    let rows = Self.rows([Self.asked(0, "问"), reply])
    let answers: [String?] = rows.map { if case .said(_, let answer) = $0.kind { answer } else { nil } }

    #expect(answers == [nil, nil, nil, "一\n\n二"])
    #expect(rows.compactMap(\.reply) == [reply.id, reply.id])
  }

  @Test func aReplyThatHasNotFinishedASentenceShowsTheDots() {
    let rows = Self.rows([Self.asked(0, "问"), Self.message(1, .reply("先说"))], live: true)

    #expect(Self.kinds(rows).last == "typing")
    #expect(rows.last?.position == .alone)
  }

  @Test func aStreamingReplyShowsOnlyFinishedSentences() {
    let rows = Self.rows([Self.asked(0, "问"), Self.message(1, .reply("先说结论。\n\n不划算。因为"))], live: true)

    #expect(Self.kinds(rows).suffix(2) == ["said 先说结论。", "said 不划算。"])
  }

  private static func item(_ title: String) throws -> Item {
    try Item(id: EntityID(), kind: .article, title: title)
  }

  private static func event(_ second: Int64, _ kind: WorldEvent.Kind) -> Conversation.Entry {
    .event(WorldEvent(id: EntityID(), at: Timestamp(millisecondsSince1970: second * 1000), kind: kind))
  }

  @Test func whatHappenedInTheLibraryBreaksARunOfBubbles() throws {
    let entries: [Conversation.Entry] = [
      .message(Self.message(0, .reply("看完去睡"))), Self.event(1, .finishedReading(try Self.item("Pingora"))),
      .message(Self.message(2, .reply("可以啊"))),
    ]
    let rows = TalkRow.rows(ConversationEntry.layout(entries, live: false), waiting: false)

    #expect(Self.kinds(rows) == ["day", "said 看完去睡", "finished Pingora", "said 可以啊"])
    #expect(rows.map(\.position) == [nil, .alone, nil, .alone])
  }

  @Test func itemsSavedOneAfterAnotherShareARowOfCardsAndWorkStillGoingIsATask() throws {
    let job = Job(item: EntityID(), stage: .download, state: .running(progress: nil))
    let entries: [Conversation.Entry] = [
      Self.event(0, .saved(try Self.item("一"), job: nil)), Self.event(1, .saved(try Self.item("二"), job: nil)),
      Self.event(2, .saved(try Self.item("三"), job: job)),
    ]
    let rows = TalkRow.rows(ConversationEntry.layout(entries, live: false), waiting: false)

    #expect(Self.kinds(rows) == ["day", "cards 一 二", "task 三"])
  }

  private static func tool(_ second: Int64, _ state: ToolActivity.State = .succeeded) -> Message {
    message(
      second,
      .tool(ToolActivity(id: "\(second)", name: "Bash", kind: .execute, subject: "loci save", output: "", state: state))
    )
  }

  @Test func itemsLociSavesDuringOneRunOfToolsGatherInOneCardUnderTheTools() {
    let rows = Self.rows([
      Self.asked(0, "存下来"), Self.tool(1), Self.message(2, .savedItem(EntityID())), Self.tool(3),
      Self.message(4, .savedItem(EntityID())), Self.message(5, .reply("存好了")),
    ])

    #expect(Self.kinds(rows) == ["day", "asked 存下来", "steps", "savedItems 2", "said 存好了"])
  }

  @Test func theToolLociIsStillRunningKeepsGoingAfterTheItemItSaved() {
    let entries = ConversationEntry.layout(
      [Self.tool(1, .running), Self.message(2, .savedItem(EntityID()))].map { .message($0) }, live: true)

    guard case .steps(let steps) = entries.first else {
      Issue.record("expected the steps first")
      return
    }
    #expect(steps.map(\.isGoing) == [true])
    #expect(steps[0].took == nil)
  }
}
