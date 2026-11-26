import Foundation
import LociModel

/// One thing the conversation shows, made from one message or from several in a row.
enum ConversationEntry: Identifiable {
  /// What the person said, with the passage they asked about.
  case asked(Message, Prompt)
  /// How a turn ended when it did not finish, or where the conversation started over.
  case aside(Message)
  case reply(Message, String, streaming: Bool)
  case saved(Message, note: EntityID)
  /// Items Loci put into the library one after another.
  case savedItems([Message])

  var id: EntityID {
    switch self {
    case .asked(let message, _), .aside(let message), .reply(let message, _, _), .saved(let message, _): message.id
    case .savedItems(let messages): messages[0].id
    }
  }

  /// A conversation's messages, oldest first, as the conversation shows them: Loci's thinking
  /// and tools, what its agent reported along the way, and what it said between tools are left out. Of a
  /// turn's replies only the last shows; while the turn runs, only one being written now, and with `hold`,
  /// only once the hold lets it. With `live`, the last one belongs to the turn running now.
  static func layout(_ said: [Conversation.Entry], live: Bool, hold: ReplyHold? = nil) -> [ConversationEntry] {
    var entries: [ConversationEntry] = []
    var savedItems: [Message] = []
    var reply: Int?
    func close() {
      if !savedItems.isEmpty { entries.append(.savedItems(savedItems)) }
      savedItems = []
    }
    let going =
      live
      ? said.lastIndex { entry in
        guard case .message(let message) = entry else { return false }
        if case .savedItem = message.body { return false }
        return true
      } : nil
    for (index, entry) in said.enumerated() {
      guard case .message(let message) = entry else { continue }
      let isLast = index == going
      switch message.body {
      case .thinking, .tool, .notice:
        continue
      case .prompt(let prompt):
        close()
        reply = nil
        entries.append(.asked(message, prompt))
      case .reply(let text):
        close()
        if let earlier = reply { entries.remove(at: earlier) }
        reply = nil
        if isLast, let hold, !hold.lets(message) { continue }
        reply = entries.count
        entries.append(.reply(message, text, streaming: isLast))
      case .savedToNote(let note):
        close()
        entries.append(.saved(message, note: note))
      case .savedItem:
        savedItems.append(message)
      case .ended, .startedOver:
        close()
        if message.body == .startedOver { reply = nil }
        entries.append(.aside(message))
      }
    }
    close()
    if live, let reply, case .reply(_, _, streaming: false) = entries[reply] { entries.remove(at: reply) }
    return entries
  }
}

/// When a reply being written may show: once it has gone on for `wait` with no tool after it. What Loci says
/// between tools is followed by a tool sooner, so it never shows.
struct ReplyHold {
  let now: Date
  let wait: Duration

  func lets(_ reply: Message) -> Bool {
    now.timeIntervalSince(reply.at.date) >= wait / .seconds(1)
  }

  /// When the reply the turn is writing now may show, if it is writing one.
  static func due(_ turn: LiveTurn?, wait: Duration) -> Date? {
    guard let last = turn?.messages.last, case .reply = last.body else { return nil }
    return last.at.date.addingTimeInterval(wait / .seconds(1))
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
        case .startedOver: close()
        default: break
        }
      case .reply(let message, let text, let going):
        texts.append(AnswerButtons.removed(from: text))
        last = message.id
        streaming = going
      case .saved, .savedItems:
        break
      }
    }
    close()
    return answers
  }
}
