import Foundation
import LociModel

@testable import LociUI

extension Sample {
  /// A finished exchange, then a turn that ran a tool, failed one, and now waits on a permission.
  func conversation() throws -> Conversation {
    var entropy = Seeded()
    func message(_ second: Double, _ body: Message.Body) -> Message {
      let date = Date(timeIntervalSince1970: 1_763_340_000 + second)
      return Message(
        id: EntityID(at: date, entropy: &entropy),
        at: Timestamp(millisecondsSince1970: Int64(date.timeIntervalSince1970 * 1000)),
        body: body)
    }
    let ask = PermissionAsk(
      id: "ask-1", title: "运行 kubectl get pods -A", tool: "call-3",
      options: [
        .init(id: "allow", role: .allow, label: nil), .init(id: "always", role: .allowAlways, label: nil),
        .init(id: "deny", role: .deny, label: nil),
      ], answer: nil)
    return Conversation(
      mentor: scheduling.id,
      messages: [
        message(0, .prompt(Prompt(text: "我想学 Kubernetes 调度", purpose: .begin))),
        message(1, .reply("好，我先写**目录**，再写第一课。")),
        message(2, .prompt(Prompt(text: "过滤阶段为什么不直接打分？", purpose: .chat))),
        message(3, .thinking("先说清约束和偏好的区别。")),
        message(4, .reply("因为约束是硬的：不满足就不能放。把它混进分数，一个很高的偏好分可能把本该排除的机器选上。")),
      ],
      turn: LiveTurn(
        startedAt: Timestamp(millisecondsSince1970: 1_763_340_010_000),
        messages: [
          message(10, .prompt(Prompt(text: "在我的集群上演示一下", purpose: .chat))),
          message(
            11,
            .tool(
              ToolActivity(
                id: "call-1", name: "read", kind: .read, subject: "lessons/filter-and-score.md", output: "",
                state: .succeeded))),
          message(
            12,
            .tool(
              ToolActivity(
                id: "call-2", name: "bash", kind: .execute, subject: "kubectl version", output: "command not found",
                state: .failed))),
          message(13, .permission(ask)),
        ]))
  }
}
