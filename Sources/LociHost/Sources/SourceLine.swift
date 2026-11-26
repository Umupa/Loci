import Foundation
import LociModel
import LociStore

/// The fetching line: beside the worker and the inbox, it fetches each source of the active homes when
/// `SourceSchedule` says it is due. Nothing a run or a turn does holds it up, and nothing it does goes
/// into the inbox but a repair or a panel's new entries. A source is fetched once at a time, and at most
/// `most` are fetched at once, pages read in a hidden web view among them. The sources tried longest ago
/// go first, and a fetch that ends looks again at once, so no source waits behind others that are due as
/// often as it is.
actor SourceLine {
  let keeper: SourceKeeper
  /// The most fetches under way at once.
  static let most = 4
  private var fetching: Set<SourceKey> = []
  /// When each source was last tried here, for one that has no snapshot to say so.
  private var tried: [SourceKey: Timestamp] = [:]

  init(keeper: SourceKeeper) {
    self.keeper = keeper
  }

  /// Starts a fetch of each source that is due and not being fetched, the longest untried first, and
  /// returns them without waiting.
  @discardableResult
  func look() async -> [Task<Void, Never>] {
    let context = keeper.context
    let environment = context.environment
    let inFront = await environment.inFront()
    let now = environment.now()
    var due: [(source: DataSource, home: Home, last: Timestamp?)] = []
    for home in context.homes() {
      let sources = context.store.dataSources(in: DataSourceFolder(home))
      guard !sources.isEmpty else { continue }
      let snapshots = (try? context.database.sourceSnapshots(Set(sources.map { SourceKey(home, $0.name) }))) ?? [:]
      for source in sources {
        let key = SourceKey(home, source.name)
        let last = [snapshots[key]?.tried, tried[key]].compactMap(\.self).max()
        guard !fetching.contains(key),
          SourceSchedule.due(source, tried: last, now: now, inFront: inFront, timeZone: environment.timeZone)
        else { continue }
        due.append((source, home, last))
      }
    }
    let first = due.sorted { ($0.last?.millisecondsSince1970 ?? .min) < ($1.last?.millisecondsSince1970 ?? .min) }
    var started: [Task<Void, Never>] = []
    for (source, home, _) in first.prefix(max(0, Self.most - fetching.count)) {
      let key = SourceKey(home, source.name)
      fetching.insert(key)
      tried[key] = now
      let keeper = keeper
      started.append(
        Task {
          await keeper.refresh(source, in: home)
          await self.finished(key)
        })
    }
    return started
  }

  private func finished(_ key: SourceKey) async {
    fetching.remove(key)
    await look()
  }
}
