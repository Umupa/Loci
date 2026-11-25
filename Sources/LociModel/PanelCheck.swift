import Foundation

/// One thing wrong with a panel, at the place in its JSON where it is, such as `pages[1].rows[2]`.
public struct PanelProblem: Hashable, Codable, Sendable, CustomStringConvertible {
  public let path: String
  public let reason: String

  public init(_ path: String, _ reason: String) {
    self.path = path
    self.reason = reason
  }

  public var description: String { path.isEmpty ? reason : "\(path): \(reason)" }
}

/// Why a panel cannot be shown: never empty.
public struct PanelProblems: Error, Hashable, Sendable {
  public let all: [PanelProblem]

  public init(all: [PanelProblem]) {
    self.all = all
  }
}

/// The one gate a panel passes on its way in, from Loci's `loci panel save` and from the files on disk: it
/// must decode and make sense, or every problem is named.
public enum PanelCheck {
  static let longestName = 32

  /// The panel in `data`, named `name` whatever the JSON says, or every problem with it.
  public static func read(_ data: Data, name: String) throws(PanelProblems) -> Panel {
    let decoded: Panel
    do {
      decoded = try JSONDecoder().decode(Panel.self, from: data)
    } catch {
      throw PanelProblems(all: [problem(decoding: error)])
    }
    let panel = Panel(
      name: name, title: decoded.title, sources: decoded.sources, follow: decoded.follow, refresh: decoded.refresh,
      feed: decoded.feed, body: decoded.body)
    let problems = problems(in: panel)
    guard problems.isEmpty else { throw PanelProblems(all: problems) }
    return panel
  }

  /// Everything wrong with a panel that decoded; empty when it can be shown.
  public static func problems(in panel: Panel) -> [PanelProblem] {
    var found = problems(ofName: panel.name)
    if panel.title.isBlank { found.append(PanelProblem("title", "is empty")) }
    if panel.follow.isBlank { found.append(PanelProblem("follow", "is empty; say what this panel follows")) }
    for (index, source) in panel.sources.enumerated() where source.isBlank {
      found.append(PanelProblem("sources[\(index)]", "is empty"))
    }
    if let refresh = panel.refresh { found += problems(in: refresh) }
    if let feed = panel.feed {
      found += DataSourceCheck.problems(ofName: feed.source).map { PanelProblem("feed.source", $0.reason) }
      if panel.refresh != nil {
        found.append(
          PanelProblem("refresh", "a panel with a feed is refreshed when its source has new entries; drop refresh"))
      }
    }
    var seen = Seen()
    switch panel.body {
    case .rows(let rows):
      found += problems(in: rows, at: "rows", seen: &seen)
    case .pages(let pages):
      if pages.isEmpty { found.append(PanelProblem("pages", "has no pages")) }
      var names: Set<String> = []
      for (index, page) in pages.enumerated() {
        let path = "pages[\(index)]"
        if page.name.isBlank {
          found.append(PanelProblem("\(path).name", "is empty"))
        } else if !names.insert(page.name).inserted {
          found.append(PanelProblem("\(path).name", "\"\(page.name)\" is used by an earlier page"))
        }
        found += problems(in: page.rows, at: "\(path).rows", seen: &seen)
      }
    }
    return found
  }

  /// A short name in lowercase English, which is also the file's: `sandbox-radar`.
  public static func problems(ofName name: String) -> [PanelProblem] {
    guard name.wholeMatch(of: /[a-z][a-z0-9]*(-[a-z0-9]+)*/) != nil, name.count <= longestName else {
      return [
        PanelProblem(
          "name", "\"\(name)\" is not a short lowercase English name, such as sandbox-radar (at most \(longestName))")
      ]
    }
    return []
  }

  private static func problems(in refresh: PanelRefresh) -> [PanelProblem] {
    var found: [PanelProblem] = []
    switch refresh.every {
    case .hour:
      break
    case .day, .week:
      if refresh.at == nil { found.append(PanelProblem("refresh.at", "is missing; write the time as HH:mm")) }
    }
    if let at = refresh.at, at.wholeMatch(of: /\d\d:\d\d/) == nil || TimeOfDay(at) == nil {
      found.append(PanelProblem("refresh.at", "\"\(at)\" is not a time written HH:mm, such as 09:30"))
    }
    switch (refresh.every, refresh.weekday) {
    case (.week, nil):
      found.append(PanelProblem("refresh.weekday", "is missing; 1 is Sunday, 7 is Saturday"))
    case (.week, let weekday?) where !(1...7).contains(weekday):
      found.append(PanelProblem("refresh.weekday", "\(weekday) is not from 1 (Sunday) to 7 (Saturday)"))
    case (.hour, _?), (.day, _?):
      found.append(PanelProblem("refresh.weekday", "is only for \"every\": \"week\""))
    default:
      break
    }
    return found
  }

  /// The ids of sections and items met so far in a panel, which each may use only once.
  private struct Seen {
    var sections: Set<String> = []
    var items: Set<String> = []
  }

  /// A panel of items needs no sentence first: the items say what there is. Nor does one that opens with a
  /// chart: its numbers do.
  private static func problems(in rows: [PanelRow], at path: String, seen: inout Seen) -> [PanelProblem] {
    guard let first = rows.first else { return [PanelProblem(path, "has no rows")] }
    var found: [PanelProblem] = []
    let holdsItems = rows.contains { if case .items = $0 { true } else { false } }
    if case .sentence = first {
    } else if !holdsItems, !first.isChart {
      found.append(PanelProblem("\(path)[0]", "the first row must be a sentence that sums the panel up"))
    }
    for (index, row) in rows.enumerated() {
      if case .items(let section) = row {
        found += problems(in: section, at: "\(path)[\(index)]", seen: &seen)
      } else {
        found += problems(in: row, at: "\(path)[\(index)]")
      }
    }
    return found
  }

  private static func problems(in section: PanelItems, at path: String, seen: inout Seen) -> [PanelProblem] {
    var found = problems(ofID: section.id, at: "\(path).id", among: &seen.sections, kind: "section")
    if let name = section.name, name.isBlank {
      found.append(PanelProblem("\(path).name", "is empty; leave it out for a section without a name"))
    }
    for (index, item) in section.items.enumerated() {
      let at = "\(path).items[\(index)]"
      found += problems(ofID: item.id, at: "\(at).id", among: &seen.items, kind: "item")
      if item.text.isBlank { found.append(PanelProblem("\(at).text", "is empty")) }
      if item.proposed, item.by == .you {
        found.append(PanelProblem("\(at).proposed", "only Loci's items are proposed"))
      }
      if let note = item.note, note.isBlank { found.append(PanelProblem("\(at).note", "is empty; leave it out")) }
      if let why = item.why {
        if item.by == .you {
          found.append(PanelProblem("\(at).why", "only Loci's items say why"))
        } else if why.isBlank {
          found.append(PanelProblem("\(at).why", "is empty; leave it out"))
        }
      }
    }
    return found
  }

  private static func problems(ofID id: String, at path: String, among seen: inout Set<String>, kind: String)
    -> [PanelProblem]
  {
    if id.isBlank { return [PanelProblem(path, "is empty")] }
    guard seen.insert(id).inserted else { return [PanelProblem(path, "\"\(id)\" is used by an earlier \(kind)")] }
    return []
  }

  private static func problems(in row: PanelRow, at path: String) -> [PanelProblem] {
    switch row {
    case .items:
      return []
    case .quotes, .line, .ruler, .allocation, .heat, .candles, .zones:
      return problems(inChart: row, at: path)
    case .sentence(let text), .label(let text):
      return text.isBlank ? [PanelProblem("\(path).text", "is empty")] : []
    case .cells(let cells):
      var found =
        (1...3).contains(cells.count) ? [] : [PanelProblem("\(path).cells", "has \(cells.count); give one to three")]
      for (index, cell) in cells.enumerated() {
        if cell.label.isBlank { found.append(PanelProblem("\(path).cells[\(index)].label", "is empty")) }
        if cell.value.isBlank { found.append(PanelProblem("\(path).cells[\(index)].value", "is empty")) }
      }
      return found
    case .list(let items):
      guard !items.isEmpty else { return [PanelProblem("\(path).items", "is empty")] }
      return items.enumerated().flatMap { index, item in problems(in: item, at: "\(path).items[\(index)]") }
    case .prominent(let title, _):
      return title.isBlank ? [PanelProblem("\(path).title", "is empty")] : []
    case .bars(let bars):
      guard !bars.isEmpty else { return [PanelProblem("\(path).bars", "is empty")] }
      return bars.enumerated().flatMap { index, bar in
        var found = share(bar.fraction, at: "\(path).bars[\(index)].fraction")
        if bar.name.isBlank { found.append(PanelProblem("\(path).bars[\(index)].name", "is empty")) }
        return found
      }
    case .picture(let url, let link):
      return place(url, at: "\(path).url") + (link.map { place($0, at: "\(path).link") } ?? [])
    }
  }

  private static func problems(in item: PanelListItem, at path: String) -> [PanelProblem] {
    var found = item.title.isBlank ? [PanelProblem("\(path).title", "is empty")] : []
    if let progress = item.progress { found += share(progress, at: "\(path).progress") }
    if let link = item.link { found += place(link, at: "\(path).link") }
    if let cover = item.cover { found += place(cover, at: "\(path).cover") }
    if let ask = item.ask, ask.isBlank { found.append(PanelProblem("\(path).ask", "is empty")) }
    return found
  }

  private static func share(_ value: Double, at path: String) -> [PanelProblem] {
    (0...1).contains(value) ? [] : [PanelProblem(path, "\(value) is not from 0 to 1")]
  }

  private static func place(_ url: URL, at path: String) -> [PanelProblem] {
    url.isWebLink || url.absoluteString.hasPrefix("loci://")
      ? [] : [PanelProblem(path, "\"\(url.absoluteString)\" is not an http(s) or loci:// link")]
  }

  private static func problem(decoding error: any Error) -> PanelProblem {
    switch error {
    case DecodingError.keyNotFound(let key, let context):
      return PanelProblem(path(context.codingPath + [key]), "is missing")
    case DecodingError.typeMismatch(let type, let context):
      return PanelProblem(path(context.codingPath), "is not \(name(of: type))")
    case DecodingError.valueNotFound(let type, let context):
      return PanelProblem(path(context.codingPath), "is null; give \(name(of: type))")
    case DecodingError.dataCorrupted(let context) where context.codingPath.isEmpty:
      return PanelProblem("", "is not JSON")
    case DecodingError.dataCorrupted(let context):
      let choices =
        switch context.codingPath.last?.stringValue {
        case "row":
          ": sentence, cells, label, list, prominent, bars, picture, items, quotes, line, ruler, allocation, heat, "
            + "candles, zones"
        case "format": ": number, percent"
        case "kind": ": take, stop"
        case "by": ": you, loci"
        case "every": ": hour, day, week"
        default: ""
        }
      if choices.isEmpty, context.debugDescription.hasPrefix("\"") {
        return PanelProblem(path(context.codingPath), context.debugDescription)
      }
      return PanelProblem(path(context.codingPath), "is not one of the values it can be\(choices)")
    default:
      return PanelProblem("", String(describing: error))
    }
  }

  private static func path(_ keys: [any CodingKey]) -> String {
    keys.reduce("") { path, key in
      if let index = key.intValue { return "\(path)[\(index)]" }
      return path.isEmpty ? key.stringValue : "\(path).\(key.stringValue)"
    }
  }

  private static func name(of type: Any.Type) -> String {
    switch type {
    case is String.Type: "text"
    case is Double.Type, is Int.Type: "a number"
    case is URL.Type: "a link"
    default: String(describing: type)
    }
  }
}

extension String {
  fileprivate var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
