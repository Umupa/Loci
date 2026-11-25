import Foundation
import LociModel
import LociStore

/// The fetching line: beside the worker and the inbox, it fetches each source of the active homes when
/// `SourceSchedule` says it is due. Nothing a run or a turn does holds it up, and nothing it does goes
/// into the inbox but a repair or a panel's new entries. A source is fetched once at a time, and at most
/// `most` are fetched at once, pages read in a hidden web view among them.
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

  /// Starts a fetch of each source that is due and not being fetched, and returns them without waiting.
  @discardableResult
  func look() async -> [Task<Void, Never>] {
    let context = keeper.context
    let environment = context.environment
    let inFront = await environment.inFront()
    let now = environment.now()
    var started: [Task<Void, Never>] = []
    for home in context.homes() {
      let sources = context.store.dataSources(in: DataSourceFolder(home))
      guard !sources.isEmpty else { continue }
      let snapshots = (try? context.database.sourceSnapshots(Set(sources.map { SourceKey(home, $0.name) }))) ?? [:]
      for source in sources {
        let key = SourceKey(home, source.name)
        let last = [snapshots[key]?.tried, tried[key]].compactMap(\.self).max()
        guard fetching.count < Self.most, !fetching.contains(key),
          SourceSchedule.due(source, tried: last, now: now, inFront: inFront, timeZone: environment.timeZone)
        else { continue }
        fetching.insert(key)
        tried[key] = now
        let keeper = keeper
        started.append(
          Task {
            await keeper.refresh(source, in: home)
            self.finished(key)
          })
      }
    }
    return started
  }

  private func finished(_ key: SourceKey) {
    fetching.remove(key)
  }
}
