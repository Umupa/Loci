import Foundation
import LociAgents
import LociModel
import LociStore

extension LocalHost {
  public func usage(since: Timestamp) async throws(HostError) -> [SessionUsage] {
    let sessions = try attempt { try database.sessions(since: since) }
    let instructions = TokenEstimate.of(store.instructions())
    let names = UsageNames(store: store, database: database)
    var usages: [SessionUsage] = []
    for session in sessions {
      guard let file = await sessionFiles.file(of: session),
        let usage = file.usage(instructions: instructions)
      else { continue }
      let work = work(of: session.owner)
      usages.append(
        SessionUsage(
          id: session.id, activity: work.activity, title: names.title(of: work.activity),
          model: usage.model ?? session.runtime.model, startedAt: session.startedAt, calls: usage.calls,
          tokens: usage.tokens, context: usage.context, makeup: usage.makeup,
          outcome: work.activity.isBackground ? (work.failed ? .failed : usage.wrote ? .made : .nothingNew) : nil))
    }
    return usages
  }

  /// What a session worked for, and whether Loci recorded that work as failed.
  private func work(of owner: SessionOwner) -> (activity: UsageActivity, failed: Bool) {
    switch owner {
    case .conversation(.main): return (.main, false)
    case .conversation(.item(let item)): return (.item(item), false)
    case .conversation(.course(let course)): return (.course(course), false)
    case .panel(let name): return (.panel(name), false)
    case .review(let day):
      if case .failed = try? database.review(of: day) { return (.review, true) }
      return (.review, false)
    case .run(let id):
      guard let run = try? database.run(id) else { return (.review, false) }
      let failed = if case .failed = run.outcome { true } else { false }
      let activity: UsageActivity =
        switch run.kind.sources.first {
        case .panel(let name, _): .panel(name)
        case .schedule(let schedule): .schedule(schedule)
        case .followUp(let followUp): .followUp(followUp)
        case .review, nil: .review
        }
      return (activity, failed)
    }
  }
}

/// The titles the usage page shows its activities by, looked up once for all sessions.
private struct UsageNames {
  let store: Store
  let schedules: [EntityID: String]
  let followUps: [EntityID: String]

  init(store: Store, database: StoreDatabase) {
    self.store = store
    schedules = Dictionary(
      ((try? database.schedules()) ?? []).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    followUps = Dictionary(
      ((try? database.followUps()) ?? []).map { ($0.id, $0.what) }, uniquingKeysWith: { first, _ in first })
  }

  func title(of activity: UsageActivity) -> String? {
    switch activity {
    case .main, .review: nil
    case .item(let item): try? store.item(item).title
    case .course(let course): try? store.course(course).title
    case .panel(let name): store.panel(named: name)?.panel?.title ?? name
    case .schedule(let schedule): schedules[schedule]
    case .followUp(let followUp): followUps[followUp]
    }
  }
}
