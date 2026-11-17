import Foundation
import LociModel
import Testing

@testable import LociUI

struct ConversationTests {
  static func turn(_ bodies: [Message.Body]) -> LiveTurn {
    LiveTurn(
      startedAt: Timestamp(millisecondsSince1970: 0),
      messages: bodies.map { Message(id: EntityID(), at: Timestamp(millisecondsSince1970: 0), body: $0) })
  }

  static let prompt = Message.Body.prompt(Prompt(text: "演示一下", purpose: .chat))

  @Test func theMentorShowsAsWorkingUntilItsReplyStartsArriving() {
    #expect(ConversationView.showsWorking(Self.turn([Self.prompt])))
    #expect(!ConversationView.showsWorking(Self.turn([Self.prompt, .reply("好")])))
  }

  @Test func aMentorWaitingForPermissionIsNotShownAsWorking() {
    let ask = PermissionAsk(
      id: "a", title: "运行 ls", tool: nil, options: [.init(id: "y", role: .allow, label: nil)], answer: nil)

    #expect(!ConversationView.showsWorking(Self.turn([Self.prompt, .permission(ask)])))
  }

  @Test func repliesKeepInlineMarkdownAndFallBackToTheTextAsWritten() {
    #expect(String(MessageRow.markdown("先写**目录**").characters) == "先写目录")
    #expect(String(MessageRow.markdown("[未闭合").characters) == "[未闭合")
  }
}
