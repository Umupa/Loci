import Foundation
import LociModel

extension Tool {
  func panel(_ request: PanelRequest, json: Bool) async throws(Failure) -> Outcome {
    switch request {
    case .save(let name): return try await save(name, json: json)
    case .list: return try await list(json: json)
    case .show(let name): return try await show(name, json: json)
    case .add(let panel, let section, let text, let proposed):
      return try await add(text, to: panel, section: section, proposed: proposed, json: json)
    }
  }

  /// Looks the panel and section up first, so Loci hears what there is when it names one that is not there.
  private func add(_ text: String, to name: String, section id: String, proposed: Bool, json: Bool)
    async throws(Failure) -> Outcome
  {
    let entries = try Failure.decoding([PanelEntry].self, from: try await line.run(ListPanels()))
    guard let panel = entries.first(where: { $0.name == name })?.panel else {
      return .failed("There is no panel \(name). Run `loci panel list` to see them.")
    }
    guard let section = panel.sections.first(where: { $0.id == id }) else {
      return .failed(PanelWords.noSection(id, in: panel))
    }
    let item = PanelItem(id: newID().description, text: text, by: .loci, proposed: proposed)
    let reply = try await line.run(EditPanel(name, .put(item, section: id, at: nil)))
    if json { return .worked(Self.text(reply)) }
    return .worked(PanelWords.added(to: panel, section: section, proposed: proposed))
  }

  /// Checks the panel here first, so Loci hears of every problem without the app being asked.
  private func save(_ name: String, json: Bool) async throws(Failure) -> Outcome {
    let panel: Panel
    do throws(PanelProblems) {
      panel = try PanelCheck.read(readInput(), name: name)
    } catch {
      return .failed(PanelWords.refused(error.all))
    }
    let reply = try await line.run(SavePanel(panel))
    return .worked(json ? Self.text(reply) : PanelWords.saved(panel))
  }

  private func list(json: Bool) async throws(Failure) -> Outcome {
    let reply = try await line.run(ListPanels())
    if json { return .worked(Self.text(reply)) }
    let entries = try Failure.decoding([PanelEntry].self, from: reply)
    guard !entries.isEmpty else { return .worked("There are no panels yet.") }
    return .worked(entries.map(PanelWords.line).joined(separator: "\n"))
  }

  private func show(_ name: String, json: Bool) async throws(Failure) -> Outcome {
    let reply = try await line.run(ListPanels())
    let entries = try Failure.decoding([PanelEntry].self, from: reply)
    guard let entry = entries.first(where: { $0.name == name }) else {
      return .failed("There is no panel \(name). Run `loci panel list` to see them.")
    }
    if json { return .worked(Self.text(try Failure.encoding(entry))) }
    return .worked(try PanelWords.entry(entry))
  }
}

/// What `loci panel` prints, for Loci to read.
enum PanelWords {
  static func refused(_ problems: [PanelProblem]) -> String {
    (["The panel was not saved. Fix each of these and save it again:"] + problems.map { "- \($0)" })
      .joined(separator: "\n")
  }

  static func noSection(_ id: String, in panel: Panel) -> String {
    let sections = panel.sections.map { section in section.id + (section.name.map { " (\($0))" } ?? "") }
    guard !sections.isEmpty else { return "\(panel.name) has no items rows to add to." }
    return "\(panel.name) has no section \"\(id)\". Its sections: \(sections.joined(separator: ", "))."
  }

  static func added(to panel: Panel, section: PanelItems, proposed: Bool) -> String {
    let place = panel.title + (section.name.map { " › \($0)" } ?? "")
    return proposed ? "Suggested in \(place); the person takes it or not." : "Added to \(place)."
  }

  static func saved(_ panel: Panel) -> String {
    "Saved \(panel.name). It is beside the main conversation now\(panel.refresh.map { ", refreshed \(every($0))" } ?? "")."
  }

  static func line(_ entry: PanelEntry) -> String {
    let title = entry.panel.map { "\($0.title)\($0.refresh.map { ", \(every($0))" } ?? "")" } ?? "(cannot be shown)"
    let broken = entry.problems.isEmpty ? "" : "  — the file has \(entry.problems.count) problem(s)"
    return "\(entry.name)  \(title)\(broken)"
  }

  static func entry(_ entry: PanelEntry) throws(Failure) -> String {
    var parts: [String] = []
    if let panel = entry.panel {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      do {
        parts.append(String(decoding: try encoder.encode(panel), as: UTF8.self))
      } catch {
        throw .unreadable(String(describing: error))
      }
    }
    if !entry.problems.isEmpty {
      let shown = entry.panel == nil ? "It cannot be shown" : "The panel shows what it last could"
      parts.append(
        (["The file has problems. \(shown):"] + entry.problems.map { "- \($0)" }).joined(separator: "\n"))
    }
    return parts.joined(separator: "\n\n")
  }

  static func every(_ refresh: PanelRefresh) -> String {
    let at = refresh.at.map { " at \($0)" } ?? ""
    switch refresh.every {
    case .hour: return "every hour"
    case .day: return "every day\(at)"
    case .week:
      let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
      let day = refresh.weekday.flatMap { days.indices.contains($0 - 1) ? days[$0 - 1] : nil } ?? "week"
      return "every \(day)\(at)"
    }
  }
}
