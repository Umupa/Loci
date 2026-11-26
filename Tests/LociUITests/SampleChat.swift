import Foundation
import LociModel

@testable import LociUI

extension Sample {
  private static func chatMessage(_ second: Double, _ body: Message.Body, _ entropy: inout Seeded) -> Message {
    let date = Date(timeIntervalSince1970: 1_763_400_000 + second)
    return Message(
      id: EntityID(at: date, entropy: &entropy),
      at: Timestamp(millisecondsSince1970: Int64(date.timeIntervalSince1970 * 1000)), body: body)
  }

  private static func tool(
    _ id: String, _ name: String, _ kind: ToolActivity.Kind, _ subject: String, output: String = "",
    state: ToolActivity.State = .succeeded
  ) -> Message.Body {
    .tool(ToolActivity(id: id, name: name, kind: kind, subject: subject, output: output, state: state))
  }

  /// A finished answer with a formula and code after a run of tools, a line where it started over, and an
  /// answer that ends on an offer.
  func chat() throws -> Conversation {
    var entropy = Seeded()
    let messages: [(Double, Message.Body)] = [
      (0, .prompt(Prompt(text: "strip 会去掉哪些字符？顺便写个脚本验证。", purpose: .chat))),
      (1, .thinking("先查文档，再写一个小脚本跑一遍。")),
      (3, Self.tool("s", "webSearch", .search, "python str.strip whitespace")),
      (5, Self.tool("c", "fileChange", .create, "/tmp/w/cleanup.py")),
      (6, Self.tool("r1", "commandExecution", .execute, "/bin/zsh -lc 'python3 cleanup.py'", output: "[Ada]\n")),
      (8, Self.tool("r2", "commandExecution", .execute, "/bin/zsh -lc 'echo $?'", output: "0\n")),
      (9, Self.tool("f", "commandExecution", .read, "/tmp/w/cleanup.py")),
      (
        10,
        .reply(
          """
          两端连续的空白都会去掉，行内公式写作 $n$ 个字符时最多比较 $2n$ 次。前 $n$ 个数的和：

          $$ \\sum_{i=1}^{n} i = \\frac{n(n+1)}{2} $$

          ```python
          name = "  Ada Lovelace "
          print(name.strip())
          ```
          """)
      ),
      (20, .startedOver),
      (30, .prompt(Prompt(text: "那 lstrip 呢？", purpose: .chat))),
      (31, Self.tool("g", "commandExecution", .execute, "/bin/zsh -lc 'python3 -c \"print(1)\"'")),
      (32, Self.tool("h", "commandExecution", .execute, "/bin/zsh -lc 'false'", state: .failed)),
      (33, .reply("lstrip 只从左边开始。要我把 rstrip 也对照着写一遍吗？")),
    ]
    return Conversation(
      ref: .main, entries: messages.map { .message(Self.chatMessage($0.0, $0.1, &entropy)) }, turn: nil,
      context: ContextUsage(used: 30_000, window: 200_000))
  }
}
