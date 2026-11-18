import Foundation
import LociModel

@testable import LociUI

extension Sample {
  /// A question about a passage answered and saved, then a turn that ran a tool and is still replying.
  func conversation() throws -> Conversation {
    var entropy = Seeded()
    func message(_ second: Double, _ body: Message.Body) -> Message {
      let date = Date(timeIntervalSince1970: 1_763_340_000 + second)
      return Message(
        id: EntityID(at: date, entropy: &entropy),
        at: Timestamp(millisecondsSince1970: Int64(date.timeIntervalSince1970 * 1000)),
        body: body)
    }
    let passage = QuotedPassage(
      locator: notes[0].locator, excerpt: "先做可行性检查，排除不满足约束的机器，剩下的才参与打分。", note: notes[0].id)
    return Conversation(
      mentor: scheduling.id,
      messages: [
        message(0, .prompt(Prompt(text: "我想学 Kubernetes 调度", purpose: .begin))),
        message(1, .prompt(Prompt(text: "为什么不直接打分？", purpose: .chat, passage: passage))),
        message(2, .thinking("先说清约束和偏好的区别，再讲混在一起会出什么错。")),
        message(
          8,
          .tool(
            ToolActivity(
              id: "call-1", name: "bash", kind: .search, subject: #"grep -n "Filter" pkg/scheduler"#, output: "",
              state: .succeeded))),
        message(
          8.4,
          .tool(
            ToolActivity(
              id: "call-2", name: "read", kind: .read, subject: "pkg/scheduler/framework/interface.go", output: "",
              state: .succeeded))),
        message(
          9.5,
          .reply(
            """
            ### 约束和偏好是两种东西

            1. **约束**是硬的：不满足就不能放，比如资源不够、端口冲突。
            2. **偏好**是软的：满足了更好，比如镜像已经在本地。
            3. 混进一个分数，一个很高的偏好分可能把本该排除的机器选上。

            所以先过滤再打分，两步各管一件事。
            """)),
        message(10, .savedToNote(notes[0].id)),
      ],
      turn: LiveTurn(
        startedAt: Timestamp(millisecondsSince1970: 1_763_340_020_000),
        messages: [
          message(20, .prompt(Prompt(text: "那打分阶段一般看哪些因素？", purpose: .chat))),
          message(21, .thinking("列出常见的打分插件。")),
          message(24, .reply("常见的有三类。资源均衡：让各节点的利用率接近。亲和")),
        ]),
      context: ContextUsage(used: 68_400, window: 200_000))
  }

  var mind: Mind {
    Mind(
      soul: """
        # Soul

        You are a mentor for one learner, teaching **Kubernetes 调度**. You write the course and its lessons, \
        answer questions on any passage, and remember what the learner knows.

        ## How you teach

        - **Anchor on what they know.** Bridge from a concept they already work with to the new one.
        - **Numbers before mechanisms.** Give the order of magnitude first, then how it works.
        """,
      memory: [
        MemoryFile(
          name: "learner.md",
          text: "三年 Go 后端，goroutine 和 channel 熟；没写过 C。\n\n喜欢先听结论和数量级，再听机制。",
          modifiedAt: Timestamp(millisecondsSince1970: 1_763_340_000_000)),
        MemoryFile(
          name: "misconceptions.md", text: "- 以为打分会排除机器。",
          modifiedAt: Timestamp(millisecondsSince1970: 1_763_250_000_000)),
      ])
  }
}
