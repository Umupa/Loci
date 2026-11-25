import Foundation
import LociModel

extension SessionFile {
  /// Reads a Codex session file (`~/.codex/sessions/<y>/<m>/<d>/rollout-<time>-<thread>.jsonl`). Each
  /// `token_count` event is one call; its input counts the cached part, which is taken out.
  public init(codex text: String) {
    self.init()
    var labels: [String: ToolLabel] = [:]
    var pending = Call(tokens: .zero)
    var total: JSONValue?
    for line in text.split(whereSeparator: \.isNewline) {
      guard let entry = JSONValue(parsing: String(line)), let payload = entry["payload"] else { continue }
      switch (entry["type"]?.string, payload["type"]?.string) {
      case ("turn_context", _):
        if let name = payload["model"]?.string { model = name }
      case ("response_item", "message") where payload["role"]?.string == "user":
        let words = Self.text(of: payload["content"])
        if calls.isEmpty, prompt.isEmpty { prompt = words } else { pending.said += TokenEstimate.of(words) }
      case ("response_item", "custom_tool_call"), ("response_item", "function_call"):
        guard let id = payload["call_id"]?.string else { continue }
        let label = Self.label(name: payload["name"]?.string ?? "tool", input: payload["input"] ?? payload["arguments"])
        labels[id] = label
        wrote = wrote || label.writes
      case ("response_item", "custom_tool_call_output"), ("response_item", "function_call_output"):
        let label = payload["call_id"]?.string.flatMap { labels[$0] }?.name ?? "tool"
        let output = payload["output"]
        pending.results[label, default: 0] += TokenEstimate.of(output?.string ?? Self.text(of: output))
      case ("event_msg", "token_count"):
        guard let info = payload["info"], let last = info["last_token_usage"], info["total_token_usage"] != total
        else { continue }
        total = info["total_token_usage"]
        let cached = last["cached_input_tokens"]?.int ?? 0
        let written = last["cache_write_input_tokens"]?.int ?? 0
        pending.tokens = TokenCounts(
          input: max(0, (last["input_tokens"]?.int ?? 0) - cached - written), cacheWrite: written, cacheRead: cached,
          output: last["output_tokens"]?.int ?? 0)
        calls.append(pending)
        pending = Call(tokens: .zero)
      default: continue
      }
    }
  }

  /// A Codex tool call by the commands it ran: `exec` runs a script whose `exec_command` calls name them,
  /// and `exec_command` and `shell` take one.
  private static func label(name: String, input: JSONValue?) -> ToolLabel {
    if name == "apply_patch" { return ToolLabel(tool: name) }
    let source = input?.string ?? input?.text ?? ""
    var commands: [String] = []
    if let arguments = JSONValue(parsing: source) {
      if let command = arguments["cmd"]?.string ?? arguments["command"]?.string { commands.append(command) }
      if let words = arguments["command"]?.array?.compactMap(\.string) { commands.append(words.joined(separator: " ")) }
    }
    for match in source.matches(of: #/cmd\s*:\s*"((?:[^"\\]|\\.)*)"/#) {
      commands.append(String(match.1).replacingOccurrences(of: #"\""#, with: "\""))
    }
    if source.contains("apply_patch") { return ToolLabel(tool: "apply_patch") }
    guard !commands.isEmpty else { return ToolLabel(tool: name) }
    return ToolLabel(command: commands.joined(separator: "\n"))
  }
}
