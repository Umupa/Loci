/// What one turn has seen so far. Records go in, the events a caller should see come out.
struct PiTurnState: Sendable {
  private var inputs: [String: JSONValue] = [:]
  private var finished: Set<String> = []
  private var failure: String?
  private var asking: [String: PiDialog] = [:]

  mutating func receive(_ event: PiEvent) -> [AgentEvent] {
    switch event {
    case .text(let delta):
      return delta.isEmpty ? [] : [.text(delta)]
    case .thinking(let delta):
      return delta.isEmpty ? [] : [.thinking(delta)]
    case .toolCallStarted(let id, let name):
      return introduce(id, name, .object([:]))
    case .toolCallComplete(let id, let name, let input):
      return introduce(id, name, input)
    case .toolRunning(let id, let name, let input):
      return introduce(id, name, input) + [.toolCallChanged(.init(id), .running)]
    case .toolOutput(let id, let text):
      guard inputs[id] != nil, !finished.contains(id), !text.isEmpty else { return [] }
      return [.toolCallChanged(.init(id), .output(text))]
    case .toolFinished(let id, let text, let failed):
      guard inputs[id] != nil, finished.insert(id).inserted else { return [] }
      return [.toolCallChanged(.init(id), .finished(output: text, failed: failed))]
    case .replyFailed(let message):
      failure = message
      return []
    case .runEnded(let willRetry):
      if willRetry { failure = nil }
      return []
    case .retrying(let attempt, let limit):
      return [.notice(.retrying(attempt: attempt, of: limit))]
    case .compacting:
      return [.notice(.compacting)]
    case .extensionFailed(let message):
      return message.isEmpty ? [] : [.notice(.message(message))]
    case .settled, .other:
      return []
    }
  }

  /// How the turn ended, once Pi has settled.
  func end(interrupted: Bool) -> TurnEnd {
    if interrupted { return .interrupted }
    if let failure { return .failed(.provider(failure)) }
    return .completed
  }

  mutating func ask(_ dialog: PiDialog) -> AgentEvent {
    asking[dialog.id] = dialog
    return .permission(dialog.request)
  }

  /// The reply to send Pi, or `nil` when nothing is waiting on that request.
  mutating func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) -> PiCommand? {
    asking.removeValue(forKey: request.value)?.reply(to: answer)
  }

  /// Dismisses every request still waiting.
  mutating func withdraw() -> [(reply: PiCommand, event: AgentEvent)] {
    defer { asking = [:] }
    return asking.values.sorted { $0.id < $1.id }.map {
      ($0.reply(to: .dismissed), .permissionClosed(.init($0.id)))
    }
  }

  private mutating func introduce(_ id: String, _ name: String, _ input: JSONValue) -> [AgentEvent] {
    guard let known = inputs[id] else {
      inputs[id] = input
      return [.toolCall(ToolCall(id: .init(id), name: name, kind: Self.kind(of: name), input: input))]
    }
    guard input != known, input != .object([:]) else { return [] }
    inputs[id] = input
    return [.toolCallChanged(.init(id), .input(input))]
  }

  private static func kind(of tool: String) -> ToolCall.Kind {
    switch tool {
    case "read": .read
    case "edit", "write": .edit
    case "bash": .execute
    case "grep", "find", "ls": .search
    default: .other
    }
  }
}
