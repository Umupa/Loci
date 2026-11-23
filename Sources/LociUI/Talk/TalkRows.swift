import Foundation
import LociModel

/// One line of a conversation as it is drawn: a bubble, or something between the bubbles.
struct TalkRow: Identifiable {
  enum Kind {
    case day(Date)
    case asked(Prompt)
    /// A part of Loci's reply. `answer` is the whole answer, on the last part of one that is finished,
    /// where it is copied from.
    case said(String, answer: String?)
    /// What Loci is doing while the next part of its reply is pending.
    case doing(Doing)
    /// Answers Loci offers at the end of the latest reply, for the person to send with one click.
    case replies([String])
    /// A turn that did not finish, said in one bubble from Loci.
    case ended(TurnEnding)
    /// Where the conversation started over.
    case startedOver
    case saved
    /// Items Loci put into the library one after another, by id: they may still be on their way, or gone.
    case savedItems([EntityID])
    /// Something long Loci wrote out, as a card that opens.
    case document(LociDocument)
    /// Links Loci gave on lines of their own, as cards; more than one makes a stack.
    case links([URL])
  }

  /// Which message a row comes from, and which part of it.
  struct ID: Hashable {
    let message: EntityID?
    let part: Int
  }

  let id: ID
  let kind: Kind
  /// For a part of a reply, the reply it belongs to, so hovering any part offers to copy the answer.
  var reply: EntityID?

  /// Whether it rises into place when it appears. The later bubbles of a reply appear where they are
  /// written, since a reply being written brings new ones several times a second.
  var arrives: Bool { id.part < 1 }

  var speaker: Speaker? {
    switch kind {
    case .asked: .person
    case .said, .ended: .loci
    case .day, .doing, .replies, .startedOver, .saved, .savedItems, .document, .links: nil
    }
  }

  /// The rows of a conversation: each reply split into bubbles, a date wherever a sitting begins, what Loci
  /// is doing while the next part of its reply is pending, and the answers the latest reply offers. With
  /// `earlier`, they go on from it: it decides whether a sitting begins.
  static func rows(_ entries: [ConversationEntry], turn: LiveTurn? = nil, after earlier: ConversationEntry? = nil)
    -> [TalkRow]
  {
    let answers = ConversationEntry.answers(entries)
    var rows: [TalkRow] = []
    var previous = earlier
    for (index, entry) in entries.enumerated() {
      if case .asked(_, let prompt) = entry, !prompt.showsPersonBubble { continue }
      if let day = Sitting.start(of: entry, after: previous) {
        rows.append(TalkRow(id: ID(message: entry.id, part: -1), kind: .day(day)))
      }
      previous = entry
      switch entry {
      case .asked(let message, let prompt):
        rows.append(TalkRow(id: ID(message: message.id, part: 0), kind: .asked(prompt)))
      case .reply(let message, let text, let streaming):
        let said = QuickReplies(text)
        let parts = BubbleLayout.bubbles(in: ReplyText.settled(said.text, streaming: streaming))
        let pieces = Self.rows(of: parts, in: message.id, answer: answers[message.id])
        rows.append(contentsOf: pieces)
        if turn == nil, index == entries.count - 1, !said.replies.isEmpty {
          rows.append(TalkRow(id: ID(message: message.id, part: pieces.count), kind: .replies(said.replies)))
        }
      case .aside(let message):
        if case .ended(let ending) = message.body {
          rows.append(TalkRow(id: ID(message: message.id, part: 0), kind: .ended(ending)))
        } else {
          rows.append(TalkRow(id: ID(message: message.id, part: 0), kind: .startedOver))
        }
      case .saved(let message, _):
        rows.append(TalkRow(id: ID(message: message.id, part: 0), kind: .saved))
      case .savedItems(let messages):
        let items = messages.compactMap { if case .savedItem(let item) = $0.body { item } else { nil } }
        rows.append(TalkRow(id: ID(message: messages[0].id, part: 0), kind: .savedItems(items)))
      }
    }
    rows = Self.joiningLinks(rows)
    if let turn, case .prompt(let prompt) = turn.messages.first?.body, prompt.showsPersonBubble,
      !Self.isSaying(turn, rows)
    {
      rows.append(TalkRow(id: ID(message: nil, part: 0), kind: .doing(Doing(turn.messages))))
    }
    return rows
  }

  /// The rows to draw: without the replies Loci offers while the person is typing their own.
  static func offered(_ rows: [TalkRow], composing: Bool) -> [TalkRow] {
    guard composing else { return rows }
    return rows.filter { if case .replies = $0.kind { false } else { true } }
  }

  /// Whether the turn's reply is what shows last, so there is nothing to say about what Loci is doing.
  private static func isSaying(_ turn: LiveTurn, _ rows: [TalkRow]) -> Bool {
    guard case .reply = turn.messages.last?.body else { return false }
    switch rows.last?.kind {
    case .said, .document, .links: return true
    default: return false
    }
  }

}
