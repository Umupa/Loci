import LociModel
import LociStore

/// Folds cards away once their deadline passes: each minute's look tells the decks when one passed since the
/// last, so every Mac's deck and this Mac's notifications drop it.
actor NextUpExpiry {
  private let context: AgentContext
  private var looked: Timestamp?

  init(context: AgentContext) {
    self.context = context
  }

  func look() async {
    let now = context.environment.now()
    defer { looked = now }
    guard let looked else { return }
    let passed = ((try? context.database.allNextUps()) ?? []).contains { card in
      guard let deadline = card.deadline else { return false }
      return looked < deadline && deadline <= now
    }
    if passed { await context.follower.follow([.nextUps]) }
  }
}
