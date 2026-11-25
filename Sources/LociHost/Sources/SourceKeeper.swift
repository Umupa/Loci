import Foundation
import LociMedia
import LociModel
import LociStore

/// What happens after a source's fetch has written its snapshot. The host is given one; by default it does
/// nothing.
protocol SourceRefreshed: Sendable {
  func refreshed(_ source: SourceKey, _ snapshot: SourceSnapshot) async
}

/// Does nothing after a fetch.
struct NothingOnRefresh: SourceRefreshed {
  func refreshed(_ source: SourceKey, _ snapshot: SourceSnapshot) async {}
}

/// Fetches sources and keeps what each fetch got, for `loci source save` and the fetching line alike. A fetch
/// that works writes the snapshot and series, offers its new entries to the panels that follow them, and is
/// handed to `refreshed`. One whose script fails often enough in a row puts a repair in the inbox, once for
/// each time it breaks.
struct SourceKeeper: Sendable {
  let context: AgentContext
  let connectors: ConnectorKeeper
  let pages: SourceService
  let refreshed: any SourceRefreshed

  private var database: StoreDatabase { context.database }

  /// One fetch, kept or not.
  func fetch(_ source: DataSource, in home: Home, at now: Timestamp) async -> Result<SourceResult, SourceFailure> {
    let key = SourceKey(home, source.name)
    let state = ((try? database.sourceSnapshot(key)) ?? nil)?.state
    let reader = SourceReader(source: key, connectors: connectors, pages: pages)
    do throws(SourceFailure) {
      return .success(
        try await context.environment.media.dataSources.fetch(source, state: state, now: now, elsewhere: reader))
    } catch {
      return .failure(error)
    }
  }

  /// Fetches the source and keeps whatever came of it.
  func refresh(_ source: DataSource, in home: Home) async {
    let now = context.environment.now()
    switch await fetch(source, in: home, at: now) {
    case .success(let result): try? await keep(result, of: source.name, in: home)
    case .failure(let failure): await keep(failure, of: source.name, in: home, at: now)
    }
  }

  /// Keeps what a fetch got: its sample, the snapshot and series, and the entries not seen before.
  func keep(_ result: SourceResult, of name: String, in home: Home) async throws(HostError) {
    let key = SourceKey(home, name)
    let snapshot = try attempt {
      try context.store.keepSample(result.sample, of: name, in: DataSourceFolder(home))
      let snapshot = try database.recordFetch(
        key, records: result.records, state: result.state, at: result.sample.at)
      let new = try database.recordEntries(key, result.entries, at: result.sample.at)
      if !new.isEmpty { offer(new, of: name, in: home, at: result.sample.at) }
      return snapshot
    }
    await refreshed.refreshed(key, snapshot)
    await context.follower.follow([.source(key), .timers])
  }

  /// Keeps a fetch that got nothing: the snapshot goes stale, and a script that failed counts toward the
  /// source's being broken. The sample a failed `parse` was given is kept until the source is broken, so
  /// its repair has the responses that broke it.
  func keep(_ failure: SourceFailure, of name: String, in home: Home, at now: Timestamp) async {
    let key = SourceKey(home, name)
    var script: SourceProblems?
    if case .script(let problems, let sample) = failure {
      script = problems
      let before = ((try? database.sourceSnapshot(key)) ?? nil)?.isBroken ?? false
      if let sample, !before { try? context.store.keepSample(sample, of: name, in: DataSourceFolder(home)) }
    }
    let snapshot = (try? database.recordFailure(key, script: script, at: now)) ?? nil
    if let snapshot, snapshot.isBroken, let since = snapshot.breakage?.since {
      raiseRepair(of: name, in: home, since: since)
    }
    await context.follower.follow([.source(key), .timers])
  }

  private func raiseRepair(of name: String, in home: Home, since: Timestamp) {
    let source = Event.Source.source(name, project: home.project)
    let open = (try? database.openEvents()) ?? []
    guard !open.contains(where: { $0.source == source }) else { return }
    _ = try? database.raise(Event(id: context.environment.newID(), source: source, due: since))
  }

  /// A refresh for each panel of the home that follows the source and lets one of the new entries through.
  private func offer(_ entries: [SourceEntry], of name: String, in home: Home, at now: Timestamp) {
    let files = context.store.home(home)
    let paused = files.panelState().paused
    let open = (try? database.openEvents()) ?? []
    for panel in files.panels().compactMap(\.panel) where !paused.contains(panel.name) {
      guard let feed = panel.feed, feed.source == name, entries.contains(where: feed.admits) else { continue }
      let source = Event.Source.panel(PanelRef(panel.name, in: home), asked: false)
      guard !open.contains(where: { $0.source.sameTimer(as: source) }) else { continue }
      _ = try? database.raise(Event(id: context.environment.newID(), source: source, due: now))
    }
  }
}
