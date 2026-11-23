import Foundation

/// What Loci may do to the items in a panel, whatever it sends: it may move, tick and drop its own items and
/// move and tick the person's, but never reword, untick or drop the person's items, nor pin or note any.
public enum PanelMerge {
  /// The panel Loci saved whole, made to keep what is the person's in `current`, the panel's file as it is.
  /// Items the person `removed` stay out. Refused when Loci dropped a section that holds the person's
  /// items.
  public static func loci(_ saved: Panel, onto current: Panel?, removed: Set<String> = []) throws(PanelProblems)
    -> Panel
  {
    guard let current else {
      return try saved.changingSections { section throws(PanelProblems) in
        section.items = section.items.map { fresh($0) }
      }
    }
    let savedIDs = Set(saved.sections.flatMap { $0.items.map(\.id) })
    let sectionIDs = Set(saved.sections.map(\.id))
    var missing: [String: [(index: Int, item: PanelItem)]] = [:]
    var problems: [PanelProblem] = []
    for section in current.sections {
      for (index, item) in section.items.enumerated() where item.by == .you && !savedIDs.contains(item.id) {
        missing[section.id, default: []].append((index, item))
      }
      if missing[section.id] != nil, !sectionIDs.contains(section.id) {
        problems.append(
          PanelProblem(
            "", "the section \"\(section.id)\" holds the person's items; keep it, with every item of theirs"))
      }
    }
    guard problems.isEmpty else { throw PanelProblems(all: problems) }
    return try saved.changingSections { section throws(PanelProblems) in
      section.items = section.items.compactMap { item in
        guard let was = current.place(of: item.id)?.item else {
          return item.by == .you || removed.contains(item.id) ? nil : fresh(item)
        }
        return kept(item, was: was)
      }
      for (index, item) in missing[section.id] ?? [] {
        section.items.insert(item, at: min(index, section.items.count))
      }
    }
  }

  /// One edit Loci makes, made to keep what is the person's in `current`; refused when it would remove or
  /// reword the person's item.
  public static func loci(_ edit: PanelEdit, on current: Panel) throws(PanelProblems) -> PanelEdit {
    switch edit {
    case .remove(let id):
      if current.place(of: id)?.item.by == .you {
        throw PanelProblems(all: [PanelProblem("", "\"\(id)\" is the person's item; only they can remove it")])
      }
      return edit
    case .put(let item, let section, let at):
      guard let was = current.place(of: item.id)?.item else { return .put(fresh(item), section: section, at: at) }
      if was.by == .you, item.text != was.text {
        throw PanelProblems(all: [PanelProblem("", "\"\(item.id)\" is the person's item; keep their words")])
      }
      return .put(kept(item, was: was), section: section, at: at)
    }
  }

  /// An item Loci writes for the first time: Loci's, not pinned, without a note.
  private static func fresh(_ item: PanelItem) -> PanelItem {
    var fresh = item
    fresh.by = .loci
    fresh.pinned = false
    fresh.note = nil
    return fresh
  }

  /// Loci's copy of an item that was there: where it is and whether it is ticked are Loci's to say, the
  /// rest stays as it was.
  private static func kept(_ item: PanelItem, was: PanelItem) -> PanelItem {
    var kept = was.by == .you ? was : item
    kept.by = was.by
    kept.done = was.done || item.done
    kept.pinned = was.pinned
    kept.note = was.note
    return kept
  }
}
