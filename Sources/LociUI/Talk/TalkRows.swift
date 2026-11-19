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
    /// Loci is at work but has said nothing yet.
    case working(since: Timestamp)
    case steps([ConversationStep])
    case aside(Message)
    case saved
    /// The person read an item to the end.
    case finished(Item, at: Date)
    /// An item going into the library, with its work still going or stopped.
    case task(Item, Job)
    /// Items that went into the library one after another, ready to open.
    case cards([Item])
  }

  /// Which message a row comes from, and which part of it.
  struct ID: Hashable {
    let message: EntityID?
    let part: Int
  }

  let id: ID
  let kind: Kind
  /// For a bubble, where it sits in its run.
  var position: BubblePosition?
  /// For a bubble, whether it answers the other speaker.
  var turn = false
  /// For a part of a reply, the reply it belongs to, so hovering any part offers to copy the answer.
  var reply: EntityID?

  var speaker: Speaker? {
    switch kind {
    case .asked: .person
    case .said: .loci
    case .day, .working, .steps, .aside, .saved, .finished, .task, .cards: nil
    }
  }

  /// The rows of a conversation, including the work status while its next reply is pending.
  static func rows(_ entries: [ConversationEntry], turn: LiveTurn? = nil) -> [TalkRow] {
    let answers = ConversationEntry.answers(entries)
    var rows: [TalkRow] = []
    for (index, entry) in entries.enumerated() {
      if let day = Sitting.start(of: entry, after: index > 0 ? entries[index - 1] : nil) {
        rows.append(TalkRow(id: ID(message: entry.id, part: -1), kind: .day(day)))
      }
      switch entry {
      case .asked(let message, let prompt):
        rows.append(TalkRow(id: ID(message: message.id, part: 0), kind: .asked(prompt)))
      case .reply(let message, let text, let streaming):
        let parts = BubbleLayout.bubbles(in: ReplyText.settled(text, streaming: streaming))
        if parts.isEmpty, streaming {
          rows.append(
            TalkRow(id: ID(message: message.id, part: 0), kind: .working(since: turn?.startedAt ?? message.at)))
        }
        for (part, words) in parts.enumerated() {
          let answer = part == parts.count - 1 ? answers[message.id] : nil
          rows.append(
            TalkRow(id: ID(message: message.id, part: part), kind: .said(words, answer: answer), reply: message.id))
        }
      case .steps(let steps):
        rows.append(TalkRow(id: ID(message: steps[0].id, part: 0), kind: .steps(steps)))
      case .aside(let message):
        rows.append(TalkRow(id: ID(message: message.id, part: 0), kind: .aside(message)))
      case .saved(let message, _):
        rows.append(TalkRow(id: ID(message: message.id, part: 0), kind: .saved))
      case .event(let event):
        rows.append(contentsOf: Self.rows(of: event))
      }
    }
    rows = Self.joiningCards(rows)
    if let turn, waitingForReply(turn) {
      rows.append(TalkRow(id: ID(message: nil, part: 0), kind: .working(since: turn.startedAt)))
    }
    let speakers = rows.map(\.speaker)
    let positions = BubbleLayout.positions(speakers)
    let turns = BubbleLayout.turns(speakers)
    for index in rows.indices {
      rows[index].position = positions[index]
      rows[index].turn = turns[index]
    }
    return rows
  }

  private static func waitingForReply(_ turn: LiveTurn) -> Bool {
    switch turn.messages.last?.body {
    case nil, .prompt: true
    case .tool(let tool): tool.state != .running
    default: false
    }
  }

  private static func rows(of event: WorldEvent) -> [TalkRow] {
    let id = ID(message: event.id, part: 0)
    switch event.kind {
    case .finishedReading(let item):
      return [TalkRow(id: id, kind: .finished(item, at: event.at.date))]
    case .saved(let item, let job?):
      return [TalkRow(id: id, kind: .task(item, job))]
    case .saved(let item, nil):
      return [TalkRow(id: id, kind: .cards([item]))]
    }
  }

  /// Cards of items saved one right after another share a row, under the first one's id.
  private static func joiningCards(_ rows: [TalkRow]) -> [TalkRow] {
    var joined: [TalkRow] = []
    for row in rows {
      if case .cards(let more) = row.kind, let last = joined.last, case .cards(let items) = last.kind {
        joined[joined.count - 1] = TalkRow(id: last.id, kind: .cards(items + more))
      } else {
        joined.append(row)
      }
    }
    return joined
  }
}
