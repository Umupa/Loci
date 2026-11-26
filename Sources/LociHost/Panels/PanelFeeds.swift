import Foundation
import LociModel
import LociStore

/// The panels that follow a source's entries: which entries wait for each, which a run is shown, and how far a
/// panel has got. A run is shown the oldest entries waiting, at most `Prompts.entriesOffered`; the panel gets
/// past them only once the run is done, and is woken again while any are still waiting, so no entry is passed
/// over because it came while a run went on or with too many others. A run that fails for good leaves its
/// entries waiting, but the panel is woken again only by entries that came after them, and not at all after
/// `PanelStuck.mostRuns` such runs in a row, until the person refreshes it.
extension AgentContext {
  /// The entries kept after the panel's place and let through by its rules, oldest first.
  func waitingEntries(of panel: Panel, in home: Home, limit: Int = .max) -> [SeenEntry] {
    guard let feed = panel.feed else { return [] }
    let after = store.home(home).panelState().fed[panel.name]
    let kept =
      (try? database.sourceEntries(SourceKey(home, feed.source), after: after, limit: StoreDatabase.entriesKept))
      ?? []
    return Array(kept.filter { feed.admits($0.entry) }.prefix(limit))
  }

  /// A refresh for each panel of the home that follows `source`'s entries and has some waiting, unless one is
  /// raised or under way already.
  func wakeFeeds(following source: String, in home: Home, at now: Timestamp) {
    let files = store.home(home)
    let panels = files.panels().compactMap(\.panel).filter { $0.feed?.source == source }
    wake(panels, in: home, at: now)
  }

  private func wake(_ panels: [Panel], in home: Home, at now: Timestamp) {
    let state = store.home(home).panelState()
    let open = (try? database.openEvents()) ?? []
    for panel in panels
    where !state.paused.contains(panel.name) && waits(panel, in: home, stuck: state.stuck[panel.name]) {
      let source = Event.Source.panel(PanelRef(panel.name, in: home), asked: false)
      guard !open.contains(where: { $0.source.sameTimer(as: source) }) else { continue }
      _ = try? database.raise(Event(id: environment.newID(), source: source, due: now))
    }
  }

  /// Whether the panel has entries for a run it was not woken for: any waiting, or once its runs failed, any
  /// that came after what they were offered, while they failed fewer than `PanelStuck.mostRuns` times.
  private func waits(_ panel: Panel, in home: Home, stuck: PanelState.PanelStuck?) -> Bool {
    guard let stuck else { return !waitingEntries(of: panel, in: home, limit: 1).isEmpty }
    guard stuck.runs < PanelState.PanelStuck.mostRuns, let feed = panel.feed else { return false }
    let later =
      (try? database.sourceEntries(SourceKey(home, feed.source), after: stuck.through, limit: StoreDatabase.entriesKept))
      ?? []
    return later.contains { feed.admits($0.entry) }
  }

  /// What a run of the panel is shown: what it was offered before, when it is tried again, or else the next
  /// entries waiting, which are kept as its offer.
  func offer(_ panel: Panel, in home: Home, to run: Run.ID) -> [SeenEntry] {
    guard let feed = panel.feed else { return [] }
    let files = store.home(home)
    if let offer = files.panelState().offers[panel.name], offer.run == run {
      let kept = (try? database.sourceEntries(SourceKey(home, feed.source), ids: offer.ids)) ?? []
      return kept.sorted { $0.seq < $1.seq }
    }
    let batch = waitingEntries(of: panel, in: home, limit: Prompts.entriesOffered)
    _ = try? files.changePanelState { state in
      state.offers[panel.name] = batch.last.map {
        PanelState.PanelOffer(run: run, ids: batch.map(\.entry.id), through: $0.seq)
      }
    }
    return batch
  }

  /// After a run of these panels is over: when it was `done`, each panel gets past what it was offered, and
  /// otherwise counts one more run that failed on it; either way the offer ends, and a panel with entries it
  /// may be woken for is woken again.
  func settleOffers(of panels: Set<String>, in home: Home, run: Run.ID, done: Bool, at now: Timestamp) {
    let files = store.home(home)
    let offered = panels.filter { files.panelState().offers[$0]?.run == run }
    guard !offered.isEmpty else { return }
    _ = try? files.changePanelState { state in
      for panel in offered {
        guard let offer = state.offers[panel] else { continue }
        if done {
          state.fed[panel] = offer.through
          state.stuck[panel] = nil
        } else {
          state.stuck[panel] = PanelState.PanelStuck(through: offer.through, runs: (state.stuck[panel]?.runs ?? 0) + 1)
        }
        state.offers[panel] = nil
      }
    }
    wake(files.panels().compactMap(\.panel).filter { offered.contains($0.name) }, in: home, at: now)
  }
}
