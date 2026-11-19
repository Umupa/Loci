import Foundation
import LociModel
import Testing

@testable import LociUI

struct ConversationTests {
  private static func layout(_ messages: [Message], live: Bool, turnStartedAt: Timestamp? = nil) -> [ConversationEntry]
  {
    ConversationEntry.layout(messages.map { .message($0) }, live: live, turnStartedAt: turnStartedAt)
  }

  private static func message(_ second: Int64, _ body: Message.Body) -> Message {
    Message(id: EntityID(), at: Timestamp(millisecondsSince1970: second * 1000), body: body)
  }

  private static let asked = message(0, .prompt(Prompt(text: "演示一下", purpose: .chat)))
  private static let read = ToolActivity(
    id: "r", name: "read", kind: .read, subject: "a.md", output: "", state: .succeeded)

  private static func steps(_ entries: [ConversationEntry]) -> [[ConversationStep]] {
    entries.compactMap { if case .steps(let steps) = $0 { steps } else { nil } }
  }

  @Test func thinkingAndToolsInARowShareOneCardAndAReplySplitsThem() {
    let entries = Self.layout(
      [
        Self.asked, Self.message(1, .thinking("想")), Self.message(2, .tool(Self.read)),
        Self.message(3, .reply("好")), Self.message(4, .tool(Self.read)),
      ], live: false)

    #expect(Self.steps(entries).map(\.count) == [2, 1])
  }

  @Test func aStepTakesUntilTheNextMessageAndOneStillGoingHasNoTime() {
    let finished = Self.layout(
      [Self.asked, Self.message(1, .thinking("想")), Self.message(7, .tool(Self.read)), Self.message(9, .reply("好"))],
      live: false)
    let going = Self.layout([Self.asked, Self.message(1, .thinking("想"))], live: true)

    #expect(Self.steps(finished).first?.map(\.took) == [.seconds(6), .seconds(2)])
    #expect(Self.steps(going).first?.map(\.took) == [nil])
    #expect(Self.steps(going).first?.map(\.isGoing) == [true])
  }

  @Test func onlyTheLastReplyOfALiveTurnIsStreaming() {
    let entries = Self.layout(
      [Self.asked, Self.message(1, .reply("一")), Self.message(2, .tool(Self.read)), Self.message(3, .reply("二"))],
      live: true)
    let streaming = entries.compactMap { if case .reply(_, _, let streaming) = $0 { streaming } else { nil } }

    #expect(streaming == [false, true])
  }

  @Test func onlyTheCurrentUnfinishedActivityHasAnElapsedClock() {
    let running = ToolActivity(id: "r", name: "read", kind: .read, subject: "a.md", output: "", state: .running)
    let thought = Self.message(2, .thinking("先看看资料"))
    let reading = Self.message(7, .tool(running))
    let finished = Self.message(7, .tool(Self.read))

    let waiting = Self.layout([Self.asked, thought], live: true, turnStartedAt: Self.asked.at)
    #expect(Self.steps(waiting).first?.map(\.activeSince) == [Self.asked.at])
    #expect(
      Self.steps(Self.layout([Self.asked, thought, reading], live: true)).first?.map(\.activeSince) == [
        nil, reading.at,
      ])
    #expect(
      Self.steps(Self.layout([Self.asked, thought, finished], live: true)).first?.map(\.activeSince) == [nil, nil])
  }

  @Test func theThinkingAndToolSymbolsStayTheSameAsWorkFinishesOrFails() {
    let thought = Self.message(1, .thinking("先看看资料"))
    let running = ToolActivity(id: "r", name: "read", kind: .read, subject: "a.md", output: "", state: .running)
    let failed = ToolActivity(id: "r", name: "read", kind: .read, subject: "a.md", output: "", state: .failed)

    #expect(Self.steps(Self.layout([Self.asked, thought], live: true)).first?.first?.symbol == Symbols.thinking)
    #expect(Self.steps(Self.layout([Self.asked, thought], live: false)).first?.first?.symbol == Symbols.thinking)
    for (tool, live) in [(running, true), (Self.read, false), (failed, false)] {
      let step = Self.steps(Self.layout([Self.asked, Self.message(2, .tool(tool))], live: live)).first?.first
      #expect(step?.symbol == Symbols.tool(.read))
    }
  }

  @Test func whatArrivedOfAStreamingReplyIsShownASentenceAtATime() {
    #expect(ReplyText.settled("第一句。第二句还没", streaming: true) == "第一句。")
    #expect(ReplyText.settled("One. Two", streaming: true) == "One.")
    #expect(ReplyText.settled("还没说完", streaming: true) == "")
    #expect(ReplyText.settled("还没说完", streaming: false) == "还没说完")
  }

  @Test func contextUsageIsShownInThousands() {
    #expect(ContextGauge.label(ContextUsage(used: 68_400, window: 200_000)) == "68k / 200k")
    #expect(ContextGauge.fraction(ContextUsage(used: 50_000, window: 200_000)) == 0.25)
    #expect(ContextGauge.fraction(ContextUsage(used: 50_000, window: nil)) == nil)
  }
}
