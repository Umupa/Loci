import LociModel

/// What has been said in a conversation, up to and including the question of the turn running now. It
/// stays the same while the answer streams.
struct SaidSoFar: Equatable {
  let entries: [Conversation.Entry]
  let asked: Message?

  init(_ entries: [Conversation.Entry], turn: LiveTurn?) {
    self.entries = entries
    asked = turn?.messages.first
  }
}

/// The turn running now, and which of its replies the hold lets show: all its rows are made from. The same
/// turn a moment later, its hold letting the same replies, draws the same rows.
struct LiveSoFar: Equatable {
  let turn: LiveTurn?
  let hold: ReplyHold

  init(_ turn: LiveTurn?, hold: ReplyHold) {
    self.turn = turn
    self.hold = hold
  }

  static func == (lhs: LiveSoFar, rhs: LiveSoFar) -> Bool {
    lhs.turn == rhs.turn && lhs.shown == rhs.shown
  }

  private var shown: [Bool] {
    turn?.messages.map(hold.lets) ?? []
  }
}

extension TalkRow {
  /// The rows of what has been said, which a streaming answer leaves as they are.
  static func settled(_ said: SaidSoFar) -> [TalkRow] {
    let asked = said.asked.map { [Conversation.Entry.message($0)] } ?? []
    return rows(ConversationEntry.layout(said.entries + asked, live: false))
  }

  /// The rows of the running turn after its question, which go on from `settled`. The reply being written
  /// shows once `hold` lets it.
  static func live(_ turn: LiveTurn?, hold: ReplyHold) -> [TalkRow] {
    guard let turn, let question = turn.messages.first, case .prompt(let prompt) = question.body else { return [] }
    let answer = turn.messages.dropFirst().map(Conversation.Entry.message)
    return rows(ConversationEntry.layout(answer, live: true, hold: hold), turn: turn, after: .asked(question, prompt))
  }

  static func live(_ said: LiveSoFar) -> [TalkRow] {
    live(said.turn, hold: said.hold)
  }
}
