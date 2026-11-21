import Foundation
import LociModel
import LociStore

/// Loci: one run per conversation, made the first time each is needed, and the daily review. Runs keep
/// going with no window open.
actor LociAgent {
  let context: AgentContext
  private var runs: [ConversationRef: AgentRun] = [:]
  /// Items being deleted. Their files are still on disk for a moment, so without this a refresh in that
  /// moment would make them a new run that outlives the deletion.
  private var leaving: Set<EntityID> = []
  private var review: Task<Void, Never>?
  private var reviewRun: AgentRun?
  private var closing = false

  init(context: AgentContext) {
    self.context = context
  }

  func run(of conversation: ConversationRef) throws(HostError) -> AgentRun {
    if case .item(let item) = conversation {
      guard !leaving.contains(item) else { throw .notFound(item.description) }
      _ = try attempt { try context.store.item(item) }
    }
    if let run = runs[conversation] { return run }
    let run = try AgentRun(owner: .conversation(conversation), session: .conversation(conversation), context: context)
    runs[conversation] = run
    return run
  }

  /// A conversation's run if it was made; asking does not make one.
  func existingRun(of conversation: ConversationRef) -> AgentRun? {
    runs[conversation]
  }

  /// Whether a turn is running anywhere, or the day is being looked back on.
  var isWorking: Bool {
    get async {
      if review != nil { return true }
      for run in runs.values where !(await run.isIdle) { return true }
      return false
    }
  }

  /// Says in the conversation's running turn that Loci put an item into the library.
  func saved(_ item: EntityID, in conversation: ConversationRef) async {
    await runs[conversation]?.saved(item)
  }

  /// Stops Loci answering on an item that is being deleted. Until `forgotten(item:)`, the item's
  /// conversation gets no run. The conversation itself stays until the deletion can no longer be undone.
  func forget(item: EntityID) async {
    leaving.insert(item)
    if let run = runs.removeValue(forKey: .item(item)) { await run.close() }
  }

  func forgotten(item: EntityID) {
    leaving.remove(item)
  }

  /// Starts looking back on a day when one is due. Returns at once; the review goes on in the background.
  func considerReview() async {
    guard review == nil, !closing else { return }
    let database = context.database
    let store = context.store
    let timeZone = context.environment.timeZone
    let situation = DailyReview.Situation(
      now: context.environment.now(), timeZone: timeZone, working: await isWorking,
      lastSaid: { (try? database.talk())?.latest },
      reviewed: { (try? database.review(of: $0)) != nil },
      active: { day in
        let start = day.start(in: timeZone)
        let end = day.adding(days: 1).start(in: timeZone)
        if ((try? database.typedMessages(from: start, to: end)) ?? 0) > 0 { return true }
        let notes = DayNotes(day: day, parsing: (try? store.dayNotes(of: day)) ?? "", title: { _ in nil })
        return !notes.notes.isEmpty
      })
    guard review == nil, !closing, let day = DailyReview.due(situation) else { return }
    review = Task { await self.lookBack(on: day) }
    await context.follower.follow([.review])
  }

  private func lookBack(on day: Day) async {
    let now = context.environment.now()
    let timeZone = context.environment.timeZone
    let previous = (try? context.database.latestReview(before: day)).flatMap { previous in
      previous.day == day.adding(days: -1) ? (previous.day, TimeOfDay(of: previous.startedAt, in: timeZone)) : nil
    }
    let outcome: ReviewOutcome
    do throws(HostError) {
      try attempt { try context.database.beginReview(of: day, at: now) }
      let run = try AgentRun(owner: .review(day), session: nil, context: context)
      reviewRun = run
      let text = context.prompts.review(of: day, since: previous.map { (day: $0.0, at: $0.1) })
      try await run.send(Prompt(text: text, purpose: .review(day)), saying: text)
      outcome = Self.outcome(of: await run.settle())
      await run.close()
    } catch {
      outcome = .failed(String(describing: error))
    }
    if closing {
      try? context.database.forgetReview(of: day)
    } else {
      try? context.database.endReview(of: day, outcome)
    }
    reviewRun = nil
    review = nil
    await context.follower.follow([.review])
  }

  private static func outcome(of turn: [Message]) -> ReviewOutcome {
    for message in turn {
      switch message.body {
      case .ended(.failed(let reason)): return .failed(reason)
      case .ended(.unstarted(let provider, .notInstalled)): return .failed("\(provider.rawValue) is not installed")
      case .ended(.unstarted(let provider, .wouldNotStart)): return .failed("\(provider.rawValue) would not start")
      case .ended(.interrupted): return .failed("stopped")
      default: continue
      }
    }
    return .finished
  }

  /// Stops every run. A review cut short is forgotten, so it is done again next time.
  func close() async {
    closing = true
    await reviewRun?.close()
    await review?.value
    for run in runs.values { await run.close() }
    runs = [:]
  }
}
