import Foundation
import LociModel

extension SessionFile {
  /// Reads a Claude Code session file (`~/.claude/projects/<folder>/<session>.jsonl`). One reply is written as
  /// several lines with the same message id and usage; it is one call.
  public init(claudeCode text: String) {
    self.init()
    var labels: [String: ToolLabel] = [:]
    var pending = Call(tokens: .zero)
    var current: String?
    for line in text.split(whereSeparator: \.isNewline) {
      guard let entry = JSONValue(parsing: String(line)), let message = entry["message"] else { continue }
      switch entry["type"]?.string {
      case "user":
        hear(message["content"], labels: labels, into: &pending)
      case "assistant":
        guard let usage = message["usage"] else { continue }
        let id = message["id"]?.string ?? entry["uuid"]?.string
        let tokens = TokenCounts(
          input: usage["input_tokens"]?.int ?? 0, cacheWrite: usage["cache_creation_input_tokens"]?.int ?? 0,
          cacheRead: usage["cache_read_input_tokens"]?.int ?? 0, output: usage["output_tokens"]?.int ?? 0)
        if id != nil, id == current, let last = calls.indices.last {
          calls[last].tokens.output = max(calls[last].tokens.output, tokens.output)
        } else {
          pending.tokens = tokens
          calls.append(pending)
          pending = Call(tokens: .zero)
          current = id
        }
        if let name = message["model"]?.string, !name.hasPrefix("<") { model = name }
        for block in message["content"]?.array ?? [] where block["type"]?.string == "tool_use" {
          guard let id = block["id"]?.string, let name = block["name"]?.string else { continue }
          let label =
            name == "Bash" ? ToolLabel(command: block["input"]?["command"]?.string ?? "") : ToolLabel(tool: name)
          labels[id] = label
          wrote = wrote || label.writes
        }
      default: continue
      }
    }
  }

  private mutating func hear(_ content: JSONValue?, labels: [String: ToolLabel], into pending: inout Call) {
    if let words = content?.string {
      if calls.isEmpty, prompt.isEmpty { prompt = words } else { pending.said += TokenEstimate.of(words) }
      return
    }
    for block in content?.array ?? [] {
      switch block["type"]?.string {
      case "tool_result":
        let label = block["tool_use_id"]?.string.flatMap { labels[$0] }?.name ?? "tool"
        pending.results[label, default: 0] += TokenEstimate.of(Self.text(of: block["content"]))
      case "text":
        let words = block["text"]?.string ?? ""
        if calls.isEmpty, prompt.isEmpty { prompt = words } else { pending.said += TokenEstimate.of(words) }
      default: continue
      }
    }
  }

  static func text(of content: JSONValue?) -> String {
    if let text = content?.string { return text }
    return (content?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n")
  }
}
