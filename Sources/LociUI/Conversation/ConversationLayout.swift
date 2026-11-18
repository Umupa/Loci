import LociModel

/// One thing the conversation shows, made from one message or from several in a row.
enum ConversationEntry: Identifiable {
  /// What the person said, with the passage they asked about.
  case asked(Message, Prompt)
  /// What Loci asked for, or how a turn went, said quietly between the messages.
  case aside(Message)
  /// The thinking and tools between two replies, in one card.
  case steps([ConversationStep])
  case reply(Message, String, streaming: Bool)
  case saved(Message, note: EntityID)

  var id: EntityID {
    switch self {
    case .asked(let message, _), .aside(let message), .reply(let message, _, _), .saved(let message, _): message.id
    case .steps(let steps): steps[0].id
    }
  }

  /// The messages of a conversation, oldest first, as the conversation shows them. With `live`, the last
  /// message belongs to the turn running now.
  static func layout(_ messages: [Message], live: Bool) -> [ConversationEntry] {
    var entries: [ConversationEntry] = []
    var steps: [ConversationStep] = []
    func close() {
      if !steps.isEmpty { entries.append(.steps(steps)) }
      steps = []
    }
    for (index, message) in messages.enumerated() {
      let next = messages.indices.contains(index + 1) ? messages[index + 1] : nil
      let isLast = next == nil && live
      switch message.body {
      case .thinking(let text):
        steps.append(ConversationStep(message: message, kind: .thinking(text), next: next, isGoing: isLast))
      case .tool(let tool):
        steps.append(ConversationStep(message: message, kind: .tool(tool), next: next, isGoing: isLast))
      case .prompt(let prompt) where prompt.purpose == .chat:
        close()
        entries.append(.asked(message, prompt))
      case .reply(let text):
        close()
        entries.append(.reply(message, text, streaming: isLast))
      case .savedToNote(let note):
        close()
        entries.append(.saved(message, note: note))
      case .prompt, .notice, .ended, .startedOver:
        close()
        entries.append(.aside(message))
      }
    }
    close()
    return entries
  }
}

extension ConversationEntry {
  /// The whole text of each finished answer, under the last reply in it, which is where it is copied from.
  /// An answer is every reply between one prompt and the next.
  static func answers(_ entries: [ConversationEntry]) -> [EntityID: String] {
    var answers: [EntityID: String] = [:]
    var texts: [String] = []
    var last: EntityID?
    var streaming = false
    func close() {
      if let last, !streaming { answers[last] = texts.joined(separator: "\n\n") }
      texts = []
      last = nil
      streaming = false
    }
    for entry in entries {
      switch entry {
      case .asked:
        close()
      case .aside(let message):
        switch message.body {
        case .prompt, .startedOver: close()
        default: break
        }
      case .reply(let message, let text, let going):
        texts.append(text)
        last = message.id
        streaming = going
      case .steps, .saved:
        break
      }
    }
    close()
    return answers
  }
}

/// A thought or a tool, and how long it took.
struct ConversationStep: Identifiable {
  let id: EntityID
  let at: Timestamp
  let kind: Kind
  /// Until the next message; `nil` while it is still going or nothing came after it.
  let took: Duration?
  /// The last thing the running turn did.
  let isGoing: Bool

  enum Kind {
    case thinking(String)
    case tool(ToolActivity)
  }

  init(message: Message, kind: Kind, next: Message?, isGoing: Bool) {
    id = message.id
    at = message.at
    self.kind = kind
    self.isGoing = isGoing
    took = next.map { .milliseconds($0.at.millisecondsSince1970 - message.at.millisecondsSince1970) }
  }
}
