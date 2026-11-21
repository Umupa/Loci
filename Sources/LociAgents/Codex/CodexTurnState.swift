struct CodexTurnState: Sendable {
  var id: String?
  private var calls: Set<String> = []
  private var finished: Set<String> = []
  private var streamed: Set<String> = []
  private var outputs: [String: String] = [:]
  /// Messages Codex marks as commentary: what it says about its work before more tools, never the reply.
  private var commentary: Set<String> = []
  private var asking: [String: CodexDialog] = [:]

  mutating func receive(_ method: String, _ params: JSONValue) -> [AgentEvent] {
    switch method {
    case "item/agentMessage/delta", "item/reasoning/summaryTextDelta", "item/reasoning/textDelta":
      let item = params["itemId"]?.string
      if let item { streamed.insert(item) }
      guard let delta = params["delta"]?.string, !delta.isEmpty else { return [] }
      let reply = method == "item/agentMessage/delta" && !commentary.contains(item ?? "")
      return [reply ? .text(delta) : .thinking(delta)]
    case "item/started", "item/completed":
      guard let item = params["item"] else { return [] }
      return receive(item, completed: method == "item/completed")
    case "item/commandExecution/outputDelta", "item/fileChange/outputDelta":
      guard let id = params["itemId"]?.string, calls.contains(id), !finished.contains(id),
        let delta = params["delta"]?.string
      else { return [] }
      outputs[id, default: ""] += delta
      return [.toolCallChanged(.init(id), .output(outputs[id] ?? ""))]
    case "thread/tokenUsage/updated":
      guard let usage = params["tokenUsage"] else { return [] }
      return [.context(.init(used: usage["last"]?["totalTokens"]?.int, window: usage["modelContextWindow"]?.int))]
    case "serverRequest/resolved":
      guard let id = params["requestId"].map(CodexDialog.key(for:)), asking.removeValue(forKey: id) != nil
      else { return [] }
      return [.permissionClosed(.init(id))]
    case "error":
      guard params["willRetry"]?.bool == true, let message = params["error"]?["message"]?.string else { return [] }
      return [.notice(.message(message))]
    default: return []
    }
  }

  mutating func ask(_ dialog: CodexDialog) -> AgentEvent {
    asking[dialog.key] = dialog
    return .permission(dialog.request)
  }

  mutating func answer(_ id: PermissionRequest.ID, with answer: PermissionAnswer) -> JSONValue? {
    asking.removeValue(forKey: id.value)?.reply(to: answer)
  }

  mutating func withdraw() -> [(reply: JSONValue, event: AgentEvent)] {
    defer { asking = [:] }
    return asking.values.sorted { $0.key < $1.key }.map {
      ($0.reply(to: .dismissed), .permissionClosed(.init($0.key)))
    }
  }

  private mutating func receive(_ item: JSONValue, completed: Bool) -> [AgentEvent] {
    guard let id = item["id"]?.string, let type = item["type"]?.string else { return [] }
    if type == "agentMessage" || type == "reasoning" {
      if item["phase"]?.string == "commentary" { commentary.insert(id) }
      guard completed, streamed.insert(id).inserted else { return [] }
      let text =
        type == "agentMessage"
        ? item["text"]?.string ?? ""
        : (item["summary"]?.array ?? []).compactMap(\.string).joined(separator: "\n")
      let reply = type == "agentMessage" && !commentary.contains(id)
      return text.isEmpty ? [] : [reply ? .text(text) : .thinking(text)]
    }
    if type == "contextCompaction" { return completed ? [] : [.notice(.compacting)] }
    let kind: ToolCall.Kind
    let name: String
    switch type {
    case "commandExecution":
      name = type
      switch item["commandActions"]?.array?.first?["type"]?.string {
      case "read": kind = .read
      case "listFiles", "search": kind = .search
      default: kind = .execute
      }
    case "fileChange":
      name = type
      let changes = item["changes"]?.array ?? []
      let kinds = Set(changes.map { $0["kind"]?["type"]?.string })
      kind = kinds == ["add"] ? .create : kinds == ["delete"] ? .delete : .edit
    case "mcpToolCall", "dynamicToolCall":
      name = item["tool"]?.string ?? type
      kind = .other
    case "webSearch":
      name = type
      kind = .search
    default: return []
    }
    var events: [AgentEvent] = []
    if calls.insert(id).inserted {
      events.append(.toolCall(.init(id: .init(id), name: name, kind: kind, input: item)))
      events.append(.toolCallChanged(.init(id), .running))
    }
    if completed, finished.insert(id).inserted {
      events.append(.toolCallChanged(.init(id), .input(item)))
      let status = item["status"]?.string
      let failed =
        status == "failed" || status == "declined" || item["success"]?.bool == false
        || (item["exitCode"]?.int.map { $0 != 0 } ?? false)
      let output =
        item["aggregatedOutput"]?.string ?? Self.text(item["result"])
        ?? item["error"]?["message"]?.string ?? outputs[id] ?? ""
      events.append(.toolCallChanged(.init(id), .finished(output: output, failed: failed)))
    }
    return events
  }

  private static func text(_ result: JSONValue?) -> String? {
    guard let content = result?["content"]?.array else { return nil }
    return content.compactMap { $0["text"]?.string }.joined(separator: "\n")
  }
}
