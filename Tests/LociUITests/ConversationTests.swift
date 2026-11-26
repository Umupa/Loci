import Foundation
import LociModel
import Testing

@testable import LociUI

struct ConversationTests {
  private static func layout(_ messages: [Message], live: Bool) -> [ConversationEntry] {
    ConversationEntry.layout(messages.map { .message($0) }, live: live)
  }

  private static func message(_ second: Int64, _ body: Message.Body) -> Message {
    Message(id: EntityID(), at: Timestamp(millisecondsSince1970: second * 1000), body: body)
  }

  private static let asked = message(0, .prompt(Prompt(text: "演示一下", purpose: .chat)))
  private static let read = ToolActivity(
    id: "r", name: "read", kind: .read, subject: "a.md", output: "", state: .succeeded)

  @Test func aLiveTurnShowsOnlyTheReplyBeingWrittenNow() {
    let entries = Self.layout(
      [Self.asked, Self.message(1, .reply("一")), Self.message(2, .tool(Self.read)), Self.message(3, .reply("二"))],
      live: true)
    let streaming = entries.compactMap { if case .reply(_, _, let streaming) = $0 { streaming } else { nil } }

    #expect(streaming == [true])
  }

  @Test func aReplyBeingWrittenShowsOnlyOnceItHasGoneOnAWhileWithNoToolAfterIt() {
    let said = [Self.asked, Self.message(1, .reply("我先查一下。"))].map { Conversation.Entry.message($0) }
    func replies(at second: TimeInterval) -> [Bool] {
      let hold = ReplyHold(now: Date(timeIntervalSince1970: second), wait: .seconds(1))
      return ConversationEntry.layout(said, live: true, hold: hold).compactMap {
        if case .reply(_, _, let streaming) = $0 { streaming } else { nil }
      }
    }

    #expect(replies(at: 1.9) == [])
    #expect(replies(at: 2) == [true])
  }

  /// DS-S6: what Loci says on its own, such as what it mended, is a message of its own after the last answer.
  @Test func whatLociSaysOnItsOwnStandsBesideTheAnswerBeforeIt() {
    let answer = Self.message(1, .reply("好的。"))
    let told = Self.message(2, .told("腾讯把价格挪到了第 4 段，parse 改从那里读。"))

    let entries = Self.layout([Self.asked, answer, told], live: false)

    let replies = entries.compactMap {
      if case .reply(let message, let text, _) = $0 { (message.id, text) } else { nil }
    }
    #expect(replies.map(\.1) == ["好的。", "腾讯把价格挪到了第 4 段，parse 改从那里读。"])
    #expect(ConversationEntry.answers(entries)[answer.id] == "好的。")
  }

  @Test func whatArrivedOfAStreamingReplyIsShownASentenceAtATime() {
    #expect(ReplyText.settled("第一句。第二句还没", streaming: true) == "第一句。")
    #expect(ReplyText.settled("One. Two", streaming: true) == "One.")
    #expect(ReplyText.settled("还没说完", streaming: true) == "")
    #expect(ReplyText.settled("还没说完", streaming: false) == "还没说完")
  }
}
