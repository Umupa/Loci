struct OpenCodeTurnState: Sendable {
  private struct Call {
    var input: JSONValue
    var output = ""
    var status: String?
  }

  private var calls: [String: Call] = [:]
  private var asking: [PermissionRequest.ID: OpenCodeDialog] = [:]

  mutating func receive(_ update: JSONValue) -> [AgentEvent] {
    switch update["sessionUpdate"]?.string {
    case "agent_message_chunk", "agent_thought_chunk":
      guard update["content"]?["type"]?.string == "text", let text = update["content"]?["text"]?.string,
        !text.isEmpty
      else { return [] }
      return update["sessionUpdate"]?.string == "agent_message_chunk" ? [.text(text)] : [.thinking(text)]
    case "tool_call", "tool_call_update":
      return tool(update)
    case "usage_update":
      return [.context(.init(used: update["used"]?.int, window: update["size"]?.int))]
    case "session_info_update":
      if update["_meta"]?["opencode/compaction"]?["status"]?.string == "started" {
        return [.notice(.compacting)]
      }
      return []
    default:
      return []
    }
  }

  mutating func ask(_ dialog: OpenCodeDialog) -> AgentEvent? {
    guard asking[dialog.request.id] == nil else { return nil }
    asking[dialog.request.id] = dialog
    return .permission(dialog.request)
  }

  mutating func answer(_ id: PermissionRequest.ID) -> OpenCodeDialog? {
    asking.removeValue(forKey: id)
  }

  mutating func withdraw() -> [OpenCodeDialog] {
    defer { asking = [:] }
    return asking.values.sorted { $0.request.id.value < $1.request.id.value }
  }

  private mutating func tool(_ update: JSONValue) -> [AgentEvent] {
    guard let id = update["toolCallId"]?.string else { return [] }
    var events: [AgentEvent] = []
    if calls[id] == nil {
      guard update["sessionUpdate"]?.string == "tool_call" else { return [] }
      let input = update["rawInput"] ?? .object([:])
      calls[id] = Call(input: input)
      events.append(
        .toolCall(
          .init(
            id: .init(id), name: update["title"]?.string ?? "OpenCode", kind: Self.kind(update["kind"]?.string),
            input: input)))
    }
    guard var call = calls[id], call.status != "completed", call.status != "failed" else { return [] }
    if let input = update["rawInput"], input != call.input {
      call.input = input
      events.append(.toolCallChanged(.init(id), .input(input)))
    }
    let output = update["content"]?.array.map { content in
      content.compactMap { $0["content"]?["text"]?.string }.joined(separator: "\n")
    }
    let changedOutput = output != nil && output != call.output
    if let output { call.output = output }
    let status = update["status"]?.string
    if status == "completed" || status == "failed" {
      events.append(.toolCallChanged(.init(id), .finished(output: call.output, failed: status == "failed")))
    } else {
      if status == "in_progress", call.status != status { events.append(.toolCallChanged(.init(id), .running)) }
      if changedOutput { events.append(.toolCallChanged(.init(id), .output(call.output))) }
    }
    if let status { call.status = status }
    calls[id] = call
    return events
  }

  private static func kind(_ value: String?) -> ToolCall.Kind {
    switch value {
    case "read": .read
    case "edit", "delete", "move": .edit
    case "execute": .execute
    case "search": .search
    default: .other
    }
  }
}
