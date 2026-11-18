import Foundation
import LociModel

@testable import LociUI

extension Sample {
  /// On Borg: a question about a passage answered and saved, then a turn that ran a tool and is still
  /// replying.
  func conversation() throws -> Conversation {
    var entropy = Seeded()
    func message(_ second: Double, _ body: Message.Body) -> Conversation.Entry {
      let date = Date(timeIntervalSince1970: 1_763_340_000 + second)
      return .message(
        Message(
          id: EntityID(at: date, entropy: &entropy),
          at: Timestamp(millisecondsSince1970: Int64(date.timeIntervalSince1970 * 1000)), body: body))
    }
    let passage = QuotedPassage(locator: notes[1].locator, excerpt: notes[1].excerpt ?? "", note: notes[1].id)
    let turn: [Conversation.Entry] = [
      message(20, .prompt(Prompt(text: "那装箱一般看哪些因素？", purpose: .chat))),
      message(21, .thinking("列出常见的打分插件。")),
      message(24, .reply("常见的有三类。\n\n资源均衡：让各节点的利用率接近。亲和")),
    ]
    return Conversation(
      ref: .item(borg.id),
      entries: [
        message(1, .prompt(Prompt(text: "超卖不怕把机器压垮吗？", purpose: .chat, passage: passage))),
        message(
          8,
          .tool(
            ToolActivity(
              id: "call-1", name: "read", kind: .read, subject: "library/borg/text.md", output: "",
              state: .succeeded))),
        message(9.5, .reply("不怕，超卖的是预留没用掉的那部分\n\n真用满时按优先级回收，低优先级的先让")),
        message(10, .savedToNote(notes[1].id)),
      ],
      turn: LiveTurn(
        startedAt: Timestamp(millisecondsSince1970: 1_763_340_020_000),
        messages: turn.compactMap { if case .message(let said) = $0 { said } else { nil } }),
      context: ContextUsage(used: 68_400, window: 200_000))
  }
}
