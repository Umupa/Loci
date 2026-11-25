import Foundation
import LociModel
import LociStore

/// The panels that follow a source's entries: Loci only names the ids it keeps, and the app writes the rows.
extension PanelKeeper {
  /// The most entries a panel that follows entries shows.
  static let picksShown = 20

  /// Writes the panel from what Loci picked: its sentence, then the picked entries filled from the source,
  /// newest pick first, before the ones shown already. From a run's session, only the panel it is for.
  func pick(_ command: PickPanelEntries, in home: Home, from session: LocalSession?) async throws(HostError) {
    let ref = PanelRef(command.panel, in: home)
    try await allow(ref, from: session)
    let files = context.store.home(home)
    guard let panel = files.panel(named: command.panel)?.panel else { throw .notFound(command.panel) }
    guard let feed = panel.feed else {
      throw .invalidRequest("\(panel.name) follows no source's entries; save it whole with loci panel save.")
    }
    let say = command.say.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !say.isEmpty else { throw .invalidRequest("Say in one sentence what is new, with --say.") }
    let key = SourceKey(home, feed.source)
    let found = try attempt { try context.database.sourceEntries(key, ids: command.ids) }
    let unknown = command.ids.filter { id in !found.contains { $0.entry.id == id } }
    guard unknown.isEmpty else {
      throw .invalidRequest(
        "\(feed.source) has no entry \(unknown.joined(separator: ", ")); pick only ids you were offered.")
    }
    let picked = command.ids.compactMap { id in found.first { $0.entry.id == id } }.map(line)
    let earlier = panel.rowsOfEveryPage.flatMap { $0 }.flatMap { row -> [PanelListItem] in
      if case .list(let lines) = row { lines } else { [] }
    }
    let lines = Array(
      (picked + earlier.filter { line in !picked.contains { $0.same(as: line) } }).prefix(Self.picksShown))
    let rows: [PanelRow] = [.sentence(say)] + (lines.isEmpty ? [] : [.list(lines)])
    let saved = panel.with(body: .rows(rows))
    let problems = PanelCheck.problems(in: saved)
    guard problems.isEmpty else { throw .invalidRequest(problems.map(\.description).joined(separator: "\n")) }
    let now = context.environment.now()
    try attempt {
      try files.savePanel(saved)
      _ = try files.changePanelState { $0.refreshed[saved.name] = now }
    }
    await context.follower.follow([.loci(.panels)])
  }

  private func line(_ seen: SeenEntry) -> PanelListItem {
    let entry = seen.entry
    let timeZone = context.environment.timeZone
    let moment = entry.at ?? seen.seen
    let day = Day(containing: moment, in: timeZone)
    let today = Day(containing: context.environment.now(), in: timeZone)
    let time = TimeOfDay(of: moment, in: timeZone)
    let at = day == today ? "\(time)" : "\(String(day.description.suffix(5))) \(time)"
    return PanelListItem(title: entry.title, subtitle: entry.note, at: at, link: entry.url)
  }
}

extension PanelListItem {
  /// The same entry, shown again.
  fileprivate func same(as other: PanelListItem) -> Bool {
    link.map { $0 == other.link } ?? (title == other.title)
  }
}
