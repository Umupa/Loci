import Foundation
import LociModel
import LociStore

/// The panels that follow a source's entries: watch triage picks entries into them as they come, and a refresh
/// the person asks for is shown the entries triage chose that the panel has not got past, at most
/// `Prompts.entriesOffered`, oldest first; the panel gets past them only once the run is done.
extension AgentContext {
  /// The entries kept after the panel's place that watch triage chose for it, oldest first.
  func waitingEntries(of panel: Panel, in home: Home, limit: Int = .max) -> [SeenEntry] {
    guard let feed = panel.feed else { return [] }
    let after = store.home(home).panelState().fed[panel.name]
    let kept =
      (try? database.sourceEntries(SourceKey(home, feed.source), after: after, limit: StoreDatabase.entriesKept))
      ?? []
    let allowed = Set(store.home(home).panelState().shownEntries[panel.name] ?? [])
    return Array(kept.filter { allowed.contains($0.entry.id) }.prefix(limit))
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

  /// After a run of these panels is over: when it was `done`, each panel gets past what it was offered; either
  /// way the offer ends.
  func settleOffers(of panels: Set<String>, in home: Home, run: Run.ID, done: Bool, at now: Timestamp) {
    let files = store.home(home)
    let offered = panels.filter { files.panelState().offers[$0]?.run == run }
    guard !offered.isEmpty else { return }
    _ = try? files.changePanelState { state in
      for panel in offered {
        guard let offer = state.offers[panel] else { continue }
        if done { state.fed[panel] = offer.through }
        state.offers[panel] = nil
      }
    }
  }
}
