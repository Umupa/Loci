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

extension TalkRow {
  /// The rows of what has been said, which a streaming answer leaves as they are.
  static func settled(_ said: SaidSoFar) -> [TalkRow] {
    let asked = said.asked.map { [Conversation.Entry.message($0)] } ?? []
    return rows(ConversationEntry.layout(said.entries + asked, live: false))
  }

  /// The rows of the running turn after its question, which go on from `settled`.
  static func live(_ turn: LiveTurn?) -> [TalkRow] {
    guard let turn, let question = turn.messages.first, case .prompt(let prompt) = question.body else { return [] }
    let answer = turn.messages.dropFirst().map(Conversation.Entry.message)
    return rows(
      ConversationEntry.layout(answer, live: true, turnStartedAt: turn.startedAt), turn: turn,
      after: .asked(question, prompt))
  }
}

extension ConversationEntry {
  /// Who says the last bubble this entry draws.
  var speaker: Speaker? {
    switch self {
    case .asked: .person
    case .reply: .loci
    case .aside, .steps, .saved, .savedItems, .event: nil
    }
  }
}
