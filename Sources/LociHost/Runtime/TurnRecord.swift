import LociAgents
import LociModel

/// The messages of one turn as they grow. Agent events go in; the turn as the interface shows it comes out.
struct TurnRecord: Sendable {
  let startedAt: Timestamp
  private(set) var messages: [Message]
  private let newID: @Sendable () -> EntityID

  init(prompt: Prompt, at time: Timestamp, newID: @escaping @Sendable () -> EntityID) {
    startedAt = time
    self.newID = newID
    messages = [Message(id: newID(), at: time, body: .prompt(prompt))]
  }

  var live: LiveTurn { LiveTurn(startedAt: startedAt, messages: messages) }

  mutating func apply(_ event: AgentEvent, at time: Timestamp) {
    switch event {
    case .text(let more):
      grow(at: time, more) {
        if case .reply(let text) = $0 { text } else { nil }
      } make: {
        .reply($0)
      }
    case .thinking(let more):
      grow(at: time, more) {
        if case .thinking(let text) = $0 { text } else { nil }
      } make: {
        .thinking($0)
      }
    case .toolCall(let call):
      add(.tool(Self.activity(call)), at: time)
    case .toolCallChanged(let id, let change):
      updateTool(id.value) { tool in Self.applying(change, to: tool) }
    case .permission(let request):
      add(.permission(Self.ask(request)), at: time)
    case .permissionClosed(let id):
      answer(id.value, .dismissed)
    case .notice(.message(let words)):
      add(.notice(words), at: time)
    case .notice, .context, .ended(.completed):
      break
    case .ended(.interrupted):
      add(.ended(.interrupted), at: time)
    case .ended(.failed(let error)):
      add(.ended(.failed(error.explanation)), at: time)
    }
  }

  /// Records the answer to a waiting request. Returns whether one was waiting.
  @discardableResult
  mutating func answer(_ request: String, _ answer: PermissionAsk.Answer) -> Bool {
    guard
      let index = messages.lastIndex(where: { message in
        if case .permission(let ask) = message.body { ask.id == request && ask.answer == nil } else { false }
      }), case .permission(let ask) = messages[index].body
    else { return false }
    let answered = PermissionAsk(id: ask.id, title: ask.title, tool: ask.tool, options: ask.options, answer: answer)
    messages[index] = Message(id: messages[index].id, at: messages[index].at, body: .permission(answered))
    return true
  }

  /// Ends the turn with a reason of Loci's own, such as an agent that would not start.
  mutating func fail(_ reason: String, at time: Timestamp) {
    add(.ended(.failed(reason)), at: time)
  }

  private mutating func add(_ body: Message.Body, at time: Timestamp) {
    messages.append(Message(id: newID(), at: time, body: body))
  }

  /// Adds to the last message when it is of the same kind, so a reply streams into one message.
  private mutating func grow(
    at time: Timestamp, _ more: String, _ text: (Message.Body) -> String?, make: (String) -> Message.Body
  ) {
    if let last = messages.last, let so = text(last.body) {
      messages[messages.count - 1] = Message(id: last.id, at: last.at, body: make(so + more))
    } else {
      add(make(more), at: time)
    }
  }

  private mutating func updateTool(_ id: String, _ change: (ToolActivity) -> ToolActivity) {
    guard
      let index = messages.lastIndex(where: { message in
        if case .tool(let tool) = message.body { tool.id == id } else { false }
      }), case .tool(let tool) = messages[index].body
    else { return }
    messages[index] = Message(id: messages[index].id, at: messages[index].at, body: .tool(change(tool)))
  }

  private static func applying(_ change: ToolCall.Change, to tool: ToolActivity) -> ToolActivity {
    switch change {
    case .input(let input):
      ToolActivity(
        id: tool.id, name: tool.name, kind: tool.kind, subject: subject(of: input) ?? tool.subject, output: tool.output,
        state: tool.state)
    case .running:
      tool
    case .output(let output):
      ToolActivity(
        id: tool.id, name: tool.name, kind: tool.kind, subject: tool.subject, output: output, state: tool.state)
    case .finished(let output, let failed):
      ToolActivity(
        id: tool.id, name: tool.name, kind: tool.kind, subject: tool.subject, output: output,
        state: failed ? .failed : .succeeded)
    }
  }

  private static func activity(_ call: ToolCall) -> ToolActivity {
    let kind: ToolActivity.Kind =
      switch call.kind {
      case .read: .read
      case .edit: .edit
      case .execute: .execute
      case .search: .search
      case .other: .other
      }
    return ToolActivity(
      id: call.id.value, name: call.name, kind: kind, subject: subject(of: call.input), output: "", state: .running)
  }

  /// What a tool works on, from the arguments agents commonly give it.
  static func subject(of input: JSONValue) -> String? {
    for key in ["command", "path", "file_path", "filePath", "pattern", "query", "url"] {
      if let value = input[key]?.string, !value.isEmpty { return value }
    }
    return nil
  }

  private static func ask(_ request: PermissionRequest) -> PermissionAsk {
    PermissionAsk(
      id: request.id.value, title: request.title, tool: request.toolCall?.value,
      options: request.options.map { option in
        let role: PermissionAsk.Role =
          switch option.role {
          case .allow: .allow
          case .allowAlways: .allowAlways
          case .deny: .deny
          case .denyAlways: .denyAlways
          case .choice: .choice
          }
        return PermissionAsk.Option(id: option.id, role: role, label: option.label)
      }, answer: nil)
  }
}

extension AgentError {
  /// The failure in words a person can act on.
  var explanation: String {
    switch self {
    case .cannotLaunch(let why): "The agent could not start: \(why)"
    case .sessionNotFound: "The earlier session could not be found."
    case .turnInProgress: "The agent is still working on the previous message."
    case .rejected(let words), .provider(let words): words
    case .exited(let code, let said): said.isEmpty ? "The agent quit with status \(code)." : said
    case .unresponsive(let command): "The agent stopped responding (\(command))."
    }
  }
}
