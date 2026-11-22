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
    let turn = live ? messages.first.map { LiveTurn(startedAt: $0.at, messages: messages) } : nil
    return TalkRow.rows(ConversationEntry.layout(messages.map { .message($0) }, live: live), turn: turn)
  }

  private static func kinds(_ rows: [TalkRow]) -> [String] {
    rows.map { row in
      switch row.kind {
      case .day: "day"
      case .asked(let prompt): "asked " + prompt.text
      case .said(let words, _): "said " + words
      case .doing(let doing): "doing \(doing)"
      case .replies(let replies): "replies " + replies.joined(separator: " ")
      case .ended: "ended"
      case .startedOver: "startedOver"
      case .saved: "saved"
      case .finished(let item, _): "finished " + item.title
      case .task(let item, _): "task " + item.title
      case .cards(let items): "cards " + items.map(\.title).joined(separator: " ")
      case .savedItems(let items): "savedItems \(items.count)"
      case .document(let document): "document " + (document.title ?? "")
      case .links(let links): "links \(links.count)"
      }
    }
  }

  @Test func aReplyArrivesAsOneBubbleForEachParagraphUnderTheQuestion() {
    let rows = Self.rows([Self.asked(0, "看到哪了"), Self.message(1, .reply("都快十二点了\n\n看到哪了"))])

    #expect(Self.kinds(rows) == ["day", "asked 看到哪了", "said 都快十二点了", "said 看到哪了"])
  }

  @Test func automaticCourseWritingKeepsTheAnswerWithoutAPersonBubble() throws {
    let lesson = try #require(Lesson.ID("raft-map"))
    for reason in [CourseEvent.WriteReason.firstLessons, .openedLastWritten] {
      let background = Self.message(
        3600, .prompt(Prompt(text: "Write raft-map", purpose: .course(.writeLesson(lesson, reason: reason)))))
      let reply = Self.message(3602, .reply("课文写好了。"))
      #expect(Self.kinds(Self.rows([background])) == [])
      let rows = Self.rows([Self.asked(0, "上一条"), Self.message(1, .reply("上一条回答")), background, reply])
      #expect(Self.kinds(rows) == ["day", "asked 上一条", "said 上一条回答", "day", "said 课文写好了。"])
      let answers = rows.compactMap { if case .said(_, let answer) = $0.kind { answer } else { nil } }
      #expect(answers == ["上一条回答", "课文写好了。"])
      let turn = LiveTurn(startedAt: background.at, messages: [background])
      #expect(TalkRow.settled(SaidSoFar([], turn: turn)).isEmpty)
    }
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

  @Test func whileLociAnswersOneLineSaysWhatItIsDoingUntilTheReplyShows() {
    let question = Self.asked(10, "问")
    let search = ToolActivity(
      id: "s", name: "webSearch", kind: .search, subject: "jailer", output: "", state: .running)

    #expect(Self.kinds(Self.rows([question], live: true)).last == "doing thinking")
    #expect(
      Self.kinds(Self.rows([question, Self.message(11, .tool(search))], live: true)).last
        == "doing searching(\"jailer\")")
    #expect(Self.kinds(Self.rows([question, Self.message(15, .reply("先说"))], live: true)).last == "doing thinking")
    #expect(Self.kinds(Self.rows([question, Self.message(15, .reply("先说。"))], live: true)).last == "said 先说。")
  }

  @Test func thinkingAndToolsNeverShowInTheConversation() {
    let tool = ToolActivity(id: "r", name: "read", kind: .read, subject: "a.md", output: "", state: .succeeded)
    let messages = [
      Self.asked(10, "问"), Self.message(11, .thinking("想")), Self.message(15, .tool(tool)),
      Self.message(16, .reply("好")),
    ]

    #expect(Self.kinds(Self.rows(messages)) == ["day", "asked 问", "said 好"])
  }

  @Test func aTurnThatDidNotFinishEndsInOneBubbleFromLoci() {
    let rows = Self.rows([
      Self.asked(0, "问"), Self.message(1, .notice("Reconnecting… 2/5")),
      Self.message(2, .ended(.failed("exit status 1: panic at src/main.rs"))),
    ])

    #expect(Self.kinds(rows) == ["day", "asked 问", "ended"])
    #expect(rows.last?.speaker == .loci)
  }

  @Test func repliesOfferedAtTheEndOfTheLatestAnswerShowUnderItWithoutTheirBlock() {
    let offer = Self.message(1, .reply("要我存进去吗？\n\n```loci-replies\n好，存进去\n先不用\n```"))
    let rows = Self.rows([Self.asked(0, "问"), offer])

    #expect(Self.kinds(rows) == ["day", "asked 问", "said 要我存进去吗？", "replies 好，存进去 先不用"])
    #expect(
      Self.kinds(Self.rows([Self.asked(0, "问"), offer, Self.asked(2, "算了")])).contains { $0.hasPrefix("replies") }
        == false)
    #expect(
      Self.kinds(Self.rows([Self.asked(0, "问"), offer], live: true)).contains { $0.hasPrefix("replies") } == false)
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
    let rows = TalkRow.rows(ConversationEntry.layout(entries, live: false))

    #expect(Self.kinds(rows) == ["day", "said 看完去睡", "finished Pingora", "said 可以啊"])
  }

  @Test func itemsSavedOneAfterAnotherShareARowOfCardsAndWorkStillGoingIsATask() throws {
    let job = Job(item: EntityID(), stage: .download, state: .running(progress: nil))
    let entries: [Conversation.Entry] = [
      Self.event(0, .saved(try Self.item("一"), job: nil)), Self.event(1, .saved(try Self.item("二"), job: nil)),
      Self.event(2, .saved(try Self.item("三"), job: job)),
    ]
    let rows = TalkRow.rows(ConversationEntry.layout(entries, live: false))

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

    #expect(Self.kinds(rows) == ["day", "asked 存下来", "savedItems 2", "said 存好了"])
  }

  @Test func whatLociSaysBetweenToolsGivesWayToItsLastReply() {
    let tool = ToolActivity(id: "r", name: "read", kind: .read, subject: "a.md", output: "", state: .succeeded)
    let messages = [
      Self.asked(0, "问"), Self.message(1, .reply("我会用 read 技能先看看。")), Self.message(2, .tool(tool)),
      Self.message(3, .reply("我再核对一下。")), Self.message(4, .tool(tool)), Self.message(5, .reply("结论是这样。")),
    ]

    #expect(Self.kinds(Self.rows(messages)) == ["day", "asked 问", "said 结论是这样。"])
    let working = Self.kinds(Self.rows(Array(messages.prefix(3)), live: true))
    #expect(working.suffix(2).first == "asked 问")
    #expect(working.last?.hasPrefix("doing") == true)
  }

  @Test func whileAReplyIsHeldBackOnlyWhatLociIsDoingShowsUntilItIsDue() {
    let tool = ToolActivity(id: "r", name: "read", kind: .read, subject: "a.md", output: "", state: .succeeded)
    let turn = LiveTurn(
      startedAt: Timestamp(millisecondsSince1970: 0),
      messages: [Self.asked(0, "问"), Self.message(1, .tool(tool)), Self.message(2, .reply("结论。"))])
    func live(at second: TimeInterval) -> [String] {
      Self.kinds(TalkRow.live(turn, hold: ReplyHold(now: Date(timeIntervalSince1970: second), wait: .seconds(1))))
    }

    #expect(live(at: 2.5).last?.hasPrefix("doing") == true)
    #expect(live(at: 3).last == "said 结论。")
    #expect(ReplyHold.due(turn, wait: .seconds(1)) == Date(timeIntervalSince1970: 3))
    #expect(
      ReplyHold.due(LiveTurn(startedAt: turn.startedAt, messages: Array(turn.messages.prefix(2))), wait: .seconds(1))
        == nil)
  }

  @Test func repliesGoAwayWhileThePersonIsTyping() {
    let offer = Self.message(1, .reply("要吗？\n\n```loci-replies\n好\n```"))
    let rows = Self.rows([Self.asked(0, "问"), offer])

    #expect(Self.kinds(TalkRow.offered(rows, composing: false)).last == "replies 好")
    #expect(Self.kinds(TalkRow.offered(rows, composing: true)).last == "said 要吗？")
  }
}
