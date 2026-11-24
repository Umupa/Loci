import Foundation
import LociModel

struct ClaudeCodeTurnState: Sendable {
  private var inputs: [String: JSONValue] = [:]
  private var finished: Set<String> = []
  private var running: Set<String> = []
  private var blocks: [Int: (id: String, json: String)] = [:]
  private var streamedText = false
  private var streamedThinking = false
  private var asking: [String: ClaudeCodeDialog] = [:]
  private var used: Int?

  mutating func receive(_ record: JSONValue) -> [AgentEvent] {
    if record["type"]?.string == "tool_progress" {
      let id =
        record["heartbeat"]?.bool == true
        ? record["parent_tool_use_id"]?.string : record["tool_use_id"]?.string
      guard let id else { return [] }
      return started(id)
    }
    if let parent = record["parent_tool_use_id"]?.string, !parent.isEmpty { return [] }
    switch record["type"]?.string {
    case "stream_event": return stream(record["event"] ?? .null)
    case "assistant": return assistant(record["message"] ?? .null)
    case "user": return results(record["message"]?["content"]?.array ?? [])
    case "control_cancel_request":
      guard let id = record["request_id"]?.string, asking.removeValue(forKey: id) != nil else { return [] }
      return [.permissionClosed(.init(id))]
    case "system":
      if record["subtype"]?.string == "compact_boundary" || record["status"]?.string == "compacting" {
        return [.notice(.compacting)]
      }
      return []
    case "result":
      var window: Int?
      if case .object(let models) = record["modelUsage"] {
        window = models.values.compactMap { $0["contextWindow"]?.int }.max()
      }
      return [.context(.init(used: used, window: window))]
    default: return []
    }
  }

  func end(_ record: JSONValue, interrupted: Bool) -> TurnEnd {
    let errors = record["errors"]?.array?.compactMap(\.string).joined(separator: "\n") ?? ""
    if interrupted || ["aborted_tools", "aborted_streaming"].contains(record["terminal_reason"]?.string ?? "") {
      return .interrupted
    }
    if record["subtype"]?.string == "success", record["is_error"]?.bool != true { return .completed }
    let message =
      errors.isEmpty ? record["result"]?.string ?? record["subtype"]?.string ?? "Claude Code failed" : errors
    return .failed(.provider(message))
  }

  mutating func ask(_ dialog: ClaudeCodeDialog) -> AgentEvent? {
    guard asking[dialog.id] == nil else { return nil }
    asking[dialog.id] = dialog
    return .permission(dialog.request)
  }

  mutating func answer(_ id: PermissionRequest.ID, with answer: PermissionAnswer) -> ClaudeCodeCommand? {
    asking.removeValue(forKey: id.value)?.reply(to: answer)
  }

  mutating func withdraw() -> [(reply: ClaudeCodeCommand, event: AgentEvent)] {
    defer { asking = [:] }
    return asking.values.sorted { $0.id < $1.id }.map {
      ($0.reply(to: .dismissed), .permissionClosed(.init($0.id)))
    }
  }

  private mutating func stream(_ event: JSONValue) -> [AgentEvent] {
    let index = event["index"]?.int ?? 0
    switch event["type"]?.string {
    case "message_start":
      streamedText = false
      streamedThinking = false
      blocks = [:]
      updateUsage(event["message"]?["usage"])
      return []
    case "content_block_start":
      let block = event["content_block"] ?? .null
      guard let id = block["id"]?.string, let name = block["name"]?.string else { return [] }
      blocks[index] = (id, "")
      return introduce(id, name, block["input"] ?? .object([:]))
    case "content_block_delta":
      let delta = event["delta"]
      switch delta?["type"]?.string {
      case "text_delta":
        streamedText = true
        let text = delta?["text"]?.string ?? ""
        return text.isEmpty ? [] : [.text(text)]
      case "thinking_delta":
        streamedThinking = true
        let text = delta?["thinking"]?.string ?? ""
        return text.isEmpty ? [] : [.thinking(text)]
      case "input_json_delta":
        blocks[index]?.json += delta?["partial_json"]?.string ?? ""
        return []
      default: return []
      }
    case "content_block_stop":
      guard let block = blocks.removeValue(forKey: index),
        let input = try? JSONDecoder().decode(JSONValue.self, from: Data(block.json.utf8)),
        input != inputs[block.id]
      else { return [] }
      inputs[block.id] = input
      return [.toolCallChanged(.init(block.id), .input(input))]
    default: return []
    }
  }

  private mutating func assistant(_ message: JSONValue) -> [AgentEvent] {
    updateUsage(message["usage"])
    return (message["content"]?.array ?? []).flatMap { block -> [AgentEvent] in
      switch block["type"]?.string {
      case "text":
        let text = block["text"]?.string ?? ""
        return streamedText || text.isEmpty ? [] : [.text(text)]
      case "thinking":
        let text = block["thinking"]?.string ?? ""
        return streamedThinking || text.isEmpty ? [] : [.thinking(text)]
      case "tool_use", "server_tool_use", "mcp_tool_use":
        guard let id = block["id"]?.string, let name = block["name"]?.string else { return [] }
        return introduce(id, name, block["input"] ?? .object([:]))
      default: return []
      }
    }
  }

  private mutating func results(_ content: [JSONValue]) -> [AgentEvent] {
    content.flatMap { block -> [AgentEvent] in
      guard block["type"]?.string == "tool_result", let id = block["tool_use_id"]?.string,
        inputs[id] != nil, finished.insert(id).inserted
      else { return [] }
      let content = block["content"]
      let text = content?.string ?? content?.array?.compactMap { $0["text"]?.string }.joined() ?? ""
      return [
        .toolCallChanged(.init(id), .finished(output: text, failed: block["is_error"]?.bool == true))
      ]
    }
  }

  private mutating func updateUsage(_ usage: JSONValue?) {
    guard let input = usage?["input_tokens"]?.int else { return }
    used =
      input + (usage?["cache_read_input_tokens"]?.int ?? 0)
      + (usage?["cache_creation_input_tokens"]?.int ?? 0) + (usage?["output_tokens"]?.int ?? 0)
  }

  private mutating func started(_ id: String) -> [AgentEvent] {
    guard inputs[id] != nil, !finished.contains(id), running.insert(id).inserted else { return [] }
    return [.toolCallChanged(.init(id), .running)]
  }

  private mutating func introduce(_ id: String, _ name: String, _ input: JSONValue) -> [AgentEvent] {
    let previous = inputs.updateValue(input, forKey: id)
    if previous == nil {
      let kind: ToolCall.Kind
      switch name {
      case "Read": kind = .read
      case "Edit", "Write", "NotebookEdit": kind = .edit
      case "Bash": kind = .execute
      case "Grep", "Glob", "WebSearch", "WebFetch": kind = .search
      default: kind = .other
      }
      return [.toolCall(.init(id: .init(id), name: name, kind: kind, input: input))]
    }
    return previous == input ? [] : [.toolCallChanged(.init(id), .input(input))]
  }
}
