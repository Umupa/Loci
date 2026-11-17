import Foundation

/// A record read from Pi's standard output.
enum PiRecord: Hashable, Sendable {
  case response(id: String?, command: String, outcome: Result<JSONValue, AgentError>)
  case dialog(PiDialog)
  /// A dialog that needs typed text, which Loci cannot answer yet.
  case unanswerable(id: String, title: String)
  case notice(Notice)
  case event(PiEvent)

  init?(line: Data) {
    guard let record = try? JSONDecoder().decode(JSONValue.self, from: line), let type = record["type"]?.string
    else { return nil }
    switch type {
    case "response":
      let command = record["command"]?.string ?? ""
      let outcome: Result<JSONValue, AgentError> =
        record["success"]?.bool == true
        ? .success(record["data"] ?? .null) : .failure(.rejected(record["error"]?.string ?? command))
      self = .response(id: record["id"]?.string, command: command, outcome: outcome)
    case "extension_ui_request":
      guard let dialog = Self.dialog(record) else { return nil }
      self = dialog
    default:
      self = .event(PiEvent(type: type, record: record))
    }
  }

  private static func dialog(_ record: JSONValue) -> PiRecord? {
    guard let id = record["id"]?.string, let method = record["method"]?.string else { return nil }
    let title = record["title"]?.string ?? ""
    switch method {
    case "confirm":
      return .dialog(PiDialog(id: id, kind: .confirm, title: title, message: record["message"]?.string ?? ""))
    case "select":
      let options = (record["options"]?.array ?? []).compactMap(\.string)
      return .dialog(PiDialog(id: id, kind: .select(options), title: title, message: ""))
    case "input", "editor":
      return .unanswerable(id: id, title: title.plain)
    case "notify":
      guard let message = record["message"]?.string?.plain, !message.isEmpty else { return nil }
      return .notice(.message(message))
    default:
      return nil
    }
  }
}

/// What Pi reports while a turn runs.
enum PiEvent: Hashable, Sendable {
  case text(String)
  case thinking(String)
  case toolCallStarted(id: String, name: String)
  case toolCallComplete(id: String, name: String, input: JSONValue)
  case toolRunning(id: String, name: String, input: JSONValue)
  case toolOutput(id: String, text: String)
  case toolFinished(id: String, text: String, failed: Bool)
  /// The model's reply ended in an error. Pi may still retry.
  case replyFailed(String)
  case runEnded(willRetry: Bool)
  case retrying(attempt: Int, of: Int)
  case compacting
  case extensionFailed(String)
  /// Pi will do nothing more on its own for this prompt.
  case settled(aborted: Bool)
  case other

  init(type: String, record: JSONValue) {
    switch type {
    case "message_update": self = Self.update(record["assistantMessageEvent"] ?? .null)
    case "message_end":
      let message = record["message"]
      if message?["role"]?.string == "assistant", message?["stopReason"]?.string == "error" {
        self = .replyFailed(message?["errorMessage"]?.string ?? "")
      } else {
        self = .other
      }
    case "tool_execution_start":
      self = Self.tool(record) { .toolRunning(id: $0, name: $1, input: Self.arguments(record["args"])) }
    case "tool_execution_update":
      self = Self.tool(record) { id, _ in .toolOutput(id: id, text: Self.text(record["partialResult"])) }
    case "tool_execution_end":
      self = Self.tool(record) { id, _ in
        .toolFinished(id: id, text: Self.text(record["result"]), failed: record["isError"]?.bool == true)
      }
    case "agent_end": self = .runEnded(willRetry: record["willRetry"]?.bool == true)
    case "agent_settled": self = .settled(aborted: record["aborted"]?.bool == true)
    case "auto_retry_start":
      self = .retrying(attempt: record["attempt"]?.int ?? 1, of: record["maxAttempts"]?.int ?? 1)
    case "compaction_start": self = .compacting
    case "extension_error": self = .extensionFailed(record["error"]?.string ?? "")
    default: self = .other
    }
  }

  private static func update(_ update: JSONValue) -> PiEvent {
    switch update["type"]?.string {
    case "text_delta": return .text(update["delta"]?.string ?? "")
    case "thinking_delta": return .thinking(update["delta"]?.string ?? "")
    case "toolcall_start":
      guard let id = update["id"]?.string, let name = update["toolName"]?.string else { return .other }
      return .toolCallStarted(id: id, name: name)
    case "toolcall_end":
      let call = update["toolCall"]
      guard let id = call?["id"]?.string, let name = call?["name"]?.string else { return .other }
      return .toolCallComplete(id: id, name: name, input: arguments(call?["arguments"]))
    default: return .other
    }
  }

  private static func tool(_ record: JSONValue, _ make: (String, String) -> PiEvent) -> PiEvent {
    guard let id = record["toolCallId"]?.string else { return .other }
    return make(id, record["toolName"]?.string ?? "")
  }

  private static func arguments(_ value: JSONValue?) -> JSONValue {
    if case .object = value { return value ?? .object([:]) }
    if let text = value?.string, let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
      case .object = parsed
    {
      return parsed
    }
    return .object([:])
  }

  private static func text(_ result: JSONValue?) -> String {
    (result?["content"]?.array ?? []).compactMap { $0["text"]?.string }.joined()
  }
}
