import LociAgents
import LociModel

/// The messages of one turn as they grow. Agent events go in; the turn as the interface shows it comes out.
struct TurnRecord: Sendable {
  let startedAt: Timestamp
  let prompt: Prompt
  private(set) var messages: [Message]
  private let newID: @Sendable () -> EntityID

  init(prompt: Prompt, at time: Timestamp, newID: @escaping @Sendable () -> EntityID) {
    startedAt = time
    self.prompt = prompt
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
    case .notice(.message(let words)):
      add(.notice(words), at: time)
    case .permission, .permissionClosed, .notice, .context, .ended(.completed):
      break
    case .ended(.interrupted):
      add(.ended(.interrupted), at: time)
    case .ended(.failed(let error)):
      add(.ended(.failed(error.explanation)), at: time)
    }
  }

  /// The reply of a turn that ended as it should, its parts joined; `nil` while there is none, or when the
  /// turn was stopped or failed.
  var answer: String? {
    var parts: [String] = []
    for message in messages {
      switch message.body {
      case .reply(let text): parts.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
      case .ended: return nil
      default: continue
      }
    }
    let answer = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    return answer.isEmpty ? nil : answer
  }

  /// Says that the question and its answer went into a note.
  mutating func saved(in note: EntityID, at time: Timestamp) {
    add(.savedToNote(note), at: time)
  }

  mutating func couldNotSave(_ reason: String, at time: Timestamp) {
    add(.notice(reason), at: time)
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
      case .create: .create
      case .execute: .execute
      case .search: .search
      case .other: .other
      }
    return ToolActivity(
      id: call.id.value, name: call.name, kind: kind, subject: subject(of: call.input), output: "", state: .running)
  }

  /// What a tool works on, from the arguments agents commonly give it: the file a command reads or a change
  /// writes, else the command, the path or the query.
  static func subject(of input: JSONValue) -> String? {
    if let action = input["commandActions"]?.array?.first, action["type"]?.string == "read",
      let path = action["path"]?.string ?? action["name"]?.string, !path.isEmpty
    {
      return path
    }
    if let path = input["changes"]?.array?.first?["path"]?.string, !path.isEmpty { return path }
    for key in ["command", "path", "file_path", "filePath", "pattern", "query", "url"] {
      if let value = input[key]?.string, !value.isEmpty { return value }
    }
    return nil
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
