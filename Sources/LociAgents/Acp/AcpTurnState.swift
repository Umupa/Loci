/// What one ACP turn has seen so far. Session updates go in, the events a caller should see come out.
struct AcpTurnState: Sendable {
  private var inputs: [String: JSONValue] = [:]
  private var running: Set<String> = []
  private var finished: Set<String> = []
  private var outputs: [String: String] = [:]
  private var asking: [String: (id: JSONValue, options: [String])] = [:]
  private let replyFailure: (@Sendable (String) -> String?)?
  private var reply = ""
  /// Tokens in the context, as the agent last reported.
  private(set) var used: Int?

  init(replyFailure: (@Sendable (String) -> String?)? = nil) {
    self.replyFailure = replyFailure
  }

  var failure: AgentError? {
    guard inputs.isEmpty, let message = replyFailure?(reply) else { return nil }
    return .provider(message)
  }

  /// The events in one `session/update` notification's params.
  mutating func receive(_ params: JSONValue) -> [AgentEvent] {
    if let total = params["_meta"]?["totalTokens"]?.int { used = total }
    guard let update = params["update"], let kind = update["sessionUpdate"]?.string else { return [] }
    switch kind {
    case "agent_message_chunk":
      guard let text = Self.text(update["content"]) else { return [] }
      if replyFailure != nil, inputs.isEmpty { reply += text }
      return [.text(text)]
    case "agent_thought_chunk":
      return Self.text(update["content"]).map { [.thinking($0)] } ?? []
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

  /// The permission request for a `session/request_permission` the agent sent with JSON-RPC id `id`.
  mutating func ask(id: JSONValue, _ params: JSONValue) -> AgentEvent {
    let key = Self.key(id)
    let call = params["toolCall"]
    let isQuestion = call?["toolCallId"]?.string?.hasPrefix("interaction_") == true
    let options = (params["options"]?.array ?? []).compactMap { option -> PermissionRequest.Option? in
      guard let id = option["optionId"]?.string else { return nil }
      return PermissionRequest.Option(
        id: id, role: isQuestion ? .choice : Self.role(option["kind"]?.string), label: option["name"]?.string)
    }
    asking[key] = (id, options.map(\.id))
    let title = call?["title"]?.string ?? Self.toolName(call ?? .null) ?? ""
    return .permission(
      PermissionRequest(
        id: .init(key), title: title, toolCall: call?["toolCallId"]?.string.map(ToolCall.ID.init),
        options: options))
  }

  /// The JSON-RPC id and result to answer with, or `nil` when nothing is waiting on that request.
  mutating func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) -> (JSONValue, JSONValue)? {
    guard let waiting = asking.removeValue(forKey: request.value) else { return nil }
    if case .chosen(let option) = answer, waiting.options.contains(option) {
      return (waiting.id, Self.selected(option))
    }
    return (waiting.id, Self.cancelled)
  }

  /// Cancels every request still waiting.
  mutating func withdraw() -> [(id: JSONValue, result: JSONValue, event: AgentEvent)] {
    defer { asking = [:] }
    return asking.sorted { $0.key < $1.key }.map { ($0.value.id, Self.cancelled, .permissionClosed(.init($0.key))) }
  }

  static let cancelled = JSONValue.object(["outcome": .object(["outcome": .string("cancelled")])])

  static func selected(_ option: String) -> JSONValue {
    .object(["outcome": .object(["outcome": .string("selected"), "optionId": .string(option)])])
  }

  static func key(_ id: JSONValue) -> String {
    if let number = id.int { return String(number) }
    return id.string ?? ""
  }

  private mutating func tool(_ update: JSONValue) -> [AgentEvent] {
    guard let id = update["toolCallId"]?.string else { return [] }
    guard !finished.contains(id) else { return [] }
    var events: [AgentEvent] = []
    let input = update["rawInput"].flatMap { if case .object = $0 { $0 } else { nil } }
    if let known = inputs[id] {
      if let input, input != known {
        inputs[id] = input
        events.append(.toolCallChanged(.init(id), .input(input)))
      }
    } else {
      let given = input ?? .object([:])
      inputs[id] = given
      let name = Self.toolName(update) ?? "tool"
      events.append(.toolCall(ToolCall(id: .init(id), name: name, kind: Self.kind(update), input: given)))
    }
    let previousOutput = outputs[id]
    if update["content"] != nil || update["rawOutput"] != nil { outputs[id] = Self.output(update) }
    switch update["status"]?.string {
    case "in_progress":
      if running.insert(id).inserted { events.append(.toolCallChanged(.init(id), .running)) }
    case "completed", "failed":
      finished.insert(id)
      events.append(
        .toolCallChanged(
          .init(id), .finished(output: outputs[id] ?? "", failed: update["status"]?.string == "failed")))
    default:
      break
    }
    if !finished.contains(id), let output = outputs[id], output != previousOutput {
      events.append(.toolCallChanged(.init(id), .output(output)))
    }
    return events
  }

  private static func text(_ content: JSONValue?) -> String? {
    guard let text = content?["text"]?.string, !text.isEmpty else { return nil }
    return text
  }

  private static func toolName(_ update: JSONValue) -> String? {
    update["_meta"]?["x.ai/tool"]?["name"]?.string ?? update["title"]?.string
  }

  private static func kind(_ update: JSONValue) -> ToolCall.Kind {
    switch update["_meta"]?["x.ai/tool"]?["kind"]?.string ?? update["kind"]?.string {
    case "read": .read
    case "edit", "delete", "move": .edit
    case "execute": .execute
    case "search", "fetch": .search
    default: .other
    }
  }

  /// What the tool printed: the agent's own text for the model when it gives one, otherwise the text
  /// content blocks.
  private static func output(_ update: JSONValue) -> String {
    if let printed = update["rawOutput"]?["output_for_prompt"]?.string { return printed }
    if let printed = update["rawOutput"]?["combinedOutput"]?.string ?? update["rawOutput"]?.string { return printed }
    return (update["content"]?.array ?? []).compactMap { $0["content"]?["text"]?.string }.joined()
  }

  private static func role(_ kind: String?) -> PermissionRequest.Option.Role {
    switch kind {
    case "allow_once": .allow
    case "allow_always": .allowAlways
    case "reject_once": .deny
    case "reject_always": .denyAlways
    default: .choice
    }
  }
}
