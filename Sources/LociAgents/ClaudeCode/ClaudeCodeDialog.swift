import LociModel

struct ClaudeCodeDialog: Hashable, Sendable {
  let id: String
  let name: String
  let input: JSONValue
  let tool: String?

  init?(_ record: JSONValue) {
    guard let id = record["request_id"]?.string,
      record["request"]?["subtype"]?.string == "can_use_tool",
      let name = record["request"]?["tool_name"]?.string
    else { return nil }
    self.id = id
    self.name = name
    self.input = record["request"]?["input"] ?? .object([:])
    self.tool = record["request"]?["tool_use_id"]?.string
  }

  var request: PermissionRequest {
    PermissionRequest(
      id: .init(id), title: name, toolCall: tool.map(ToolCall.ID.init),
      options: [.init(id: "allow", role: .allow), .init(id: "deny", role: .deny)])
  }

  func reply(to answer: PermissionAnswer) -> ClaudeCodeCommand {
    .reply(self, allow: answer == .chosen("allow"))
  }
}
