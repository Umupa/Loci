import LociModel
import LociStore

extension AgentRun {
  /// Saves a question about a passage, with the turn's answer, in the passage's note, and says so in the
  /// turn. Does nothing when the turn asked about no passage, ended without an answer, or the note was
  /// deleted meanwhile. A note that cannot be written is said in the turn instead.
  func saveAnswer(of turn: inout TurnRecord) async {
    guard let quoted = turn.prompt.passage, let answer = turn.answer else { return }
    let now = context.environment.now()
    let store = context.store
    let content = quoted.locator.content
    do {
      guard let note = store.notes(on: content).value.first(where: { $0.id == quoted.note }) else { return }
      let exchange = try Note.Exchange(
        question: turn.prompt.text, answer: answer, askedAt: turn.startedAt)
      let saved = try Note(
        id: note.id, locator: note.locator, excerpt: note.excerpt, thought: note.thought,
        exchanges: note.exchanges + [exchange], savedAt: now)
      try store.append(.saved(saved), on: content)
    } catch {
      turn.couldNotSave(String(describing: error), at: now)
      return
    }
    turn.saved(in: quoted.note, at: now)
    await context.follower.follow([.notes(content)])
  }
}
