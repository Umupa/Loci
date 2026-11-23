import Foundation
import LociModel

/// What Loci is shown each turn of what the person wrote in panels and their take on what is there: the
/// person's items still to do, Loci's items they pinned or noted, Loci's suggestions they have not taken, and
/// list lines they pinned, noted or hid. Kept short.
enum PanelSummary {
  static let limit = 20
  static let characters = 2_000
  /// How the summary is headed in the turn's context.
  static let heading = "Panels (what the person wrote and marked)"

  static func of(_ panels: [Panel], marks: [String: [PanelLineKey: PanelLineMark]]) -> String {
    let lines = panels.flatMap { panel in
      items(in: panel) + proposals(in: panel) + Self.lines(of: panel, marks: marks[panel.name] ?? [:])
    }
    var kept: [String] = []
    var length = 0
    for line in lines {
      guard kept.count < limit, length + line.count <= characters else { break }
      kept.append(line)
      length += line.count + 1
    }
    if kept.count < lines.count { kept.append("…and \(lines.count - kept.count) more.") }
    return kept.joined(separator: "\n")
  }

  /// Whether there is anything a summary could say: a panel with items, or a take on a line.
  static func applies(to panels: [Panel], marks: [String: [PanelLineKey: PanelLineMark]]) -> Bool {
    panels.contains { !$0.sections.isEmpty } || marks.values.contains { !$0.isEmpty }
  }

  private static func items(in panel: Panel) -> [String] {
    panel.sections.flatMap { section in
      section.items.compactMap { item -> String? in
        let take = (item.pinned ? " [pinned]" : "") + (item.note.map { " [note: \($0)]" } ?? "")
        let place = "- \(panel.title)" + (section.name.map { " › \($0)" } ?? "") + ": "
        switch item.by {
        case .you: return item.done ? nil : place + item.text + take
        case .loci: return take.isEmpty ? nil : place + item.text + " [yours]" + take
        }
      }
    }
  }

  private static func proposals(in panel: Panel) -> [String] {
    let count = panel.sections.reduce(0) { $0 + $1.items.count(where: \.proposed) }
    return count == 0 ? [] : ["- \(panel.title): \(count) of your suggestions not taken yet"]
  }

  private static func lines(of panel: Panel, marks: [PanelLineKey: PanelLineMark]) -> [String] {
    marks.sorted { $0.key.rawValue < $1.key.rawValue }.map { key, mark in
      let take = mark.hidden ? "hidden" : mark.pinned ? "pinned" : "noted"
      return "- \(panel.title): \(take) \"\(key.rawValue)\"" + (mark.note.map { " [note: \($0)]" } ?? "")
    }
  }
}
