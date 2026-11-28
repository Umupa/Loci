import Foundation
import LociModel
import LociStore

/// The fetching line: beside the worker and the inbox, it fetches each source of the active homes when
/// `SourceSchedule` says it is due, and looks at each follow once an hour. Nothing a run or a turn does holds
/// it up, and nothing it does goes into the inbox but a repair: what a fetch brings that is new goes to watch
/// triage, and a follow's new episodes only to its follow page. A source or a follow is fetched once at a
/// time, at most `most` are fetched at once, pages read in a hidden web view among them, and at most
/// `startsPerMinute` start in a minute, sources and follows alike. Those tried longest ago go first, and a
/// fetch that ends looks again at once, so nothing waits behind others that are due as often as it is.
actor SourceLine {
  let keeper: SourceKeeper
  let follows: FollowKeeper?
  /// The most fetches under way at once.
  static let most = 4
  /// The most fetches started in any minute, however many sources are due: the rest wait their turn.
  static let startsPerMinute = 12
  /// When each fetch of the last minute started.
  private var starts: [Timestamp] = []
  private var fetching: Set<Fetch> = []
  /// When each source was last tried here, for one that has no snapshot to say so.
  private var tried: [SourceKey: Timestamp] = [:]

  /// One thing the line fetches.
  private enum Fetch: Hashable {
    case source(SourceKey)
    case follow(EntityID)
  }

  private struct Due {
    let fetch: Fetch
    let last: Timestamp?
    let run: @Sendable () async -> Void
  }

  init(keeper: SourceKeeper, follows: FollowKeeper? = nil) {
    self.keeper = keeper
    self.follows = follows
  }

  /// Starts a fetch of each source and follow that is due and not being fetched, the longest untried first,
  /// and returns them without waiting.
  @discardableResult
  func look() async -> [Task<Void, Never>] {
    let now = keeper.context.environment.now()
    starts.removeAll { now.millisecondsSince1970 - $0.millisecondsSince1970 >= 60_000 }
    let available = min(Self.most - fetching.count, Self.startsPerMinute - starts.count)
    guard available > 0 else { return [] }
    let due = (sources(due: now) + followsDue(at: now)).filter { !fetching.contains($0.fetch) }
    let first = due.sorted { ($0.last?.millisecondsSince1970 ?? .min) < ($1.last?.millisecondsSince1970 ?? .min) }
    var started: [Task<Void, Never>] = []
    for each in first.prefix(available) {
      fetching.insert(each.fetch)
      if case .source(let key) = each.fetch { tried[key] = now }
      starts.append(now)
      started.append(
        Task {
          await each.run()
          await self.finished(each.fetch)
        })
    }
    return started
  }

  private func sources(due now: Timestamp) -> [Due] {
    let context = keeper.context
    var due: [Due] = []
    for home in context.homes() {
      let sources = context.store.dataSources(in: DataSourceFolder(home))
      guard !sources.isEmpty else { continue }
      let snapshots = (try? context.database.sourceSnapshots(Set(sources.map { SourceKey(home, $0.name) }))) ?? [:]
      for source in sources {
        let key = SourceKey(home, source.name)
        let last = [snapshots[key]?.tried, tried[key]].compactMap(\.self).max()
        guard SourceSchedule.due(source, tried: last, now: now, timeZone: context.environment.timeZone) else {
          continue
        }
        let keeper = keeper
        due.append(Due(fetch: .source(key), last: last) { await keeper.refresh(source, in: home) })
      }
    }
    return due
  }

  private func followsDue(at now: Timestamp) -> [Due] {
    guard let follows else { return [] }
    return follows.due(at: now).map { follow, tried in
      Due(fetch: .follow(follow.id), last: tried) { await follows.look(follow) }
    }
  }

  private func finished(_ fetch: Fetch) async {
    fetching.remove(fetch)
    await look()
  }
}
