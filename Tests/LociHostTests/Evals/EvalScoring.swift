import Foundation
import LociModel

/// What a run left behind that the eval looks at: the panel's lines the companion wrote, the notes the run
/// added, and how many messages the main conversation has.
struct EvalSnapshot: Sendable, Codable {
  struct Entry: Hashable, Sendable, Codable {
    /// What the person would call the same line: its link, or its words.
    let key: String
    let text: String
  }

  let entries: [Entry]
  /// Today's note lines tagged with this run.
  let notes: [String]
  let mainMessages: Int

  static let empty = EvalSnapshot(entries: [], notes: [], mainMessages: 0)

  /// The companion's lines in a panel: list lines and the items it wrote, and a prominent line. The first
  /// sentence sums the panel up and may change every run, so it is not a line.
  static func entries(of panel: Panel?) -> [Entry] {
    guard let panel else { return [] }
    let rows: [PanelRow] =
      switch panel.body {
      case .rows(let rows): rows
      case .pages(let pages): pages.flatMap(\.rows)
      }
    return rows.flatMap { row -> [Entry] in
      switch row {
      case .list(let lines):
        lines.map { Entry(key: PanelLineKey($0).rawValue, text: [$0.title, $0.subtitle ?? ""].joined(separator: " ")) }
      case .items(let items):
        items.items.filter { $0.by == .loci }.map {
          Entry(key: $0.text, text: [$0.text, $0.why ?? ""].joined(separator: " "))
        }
      case .prominent(let title, let subtitle):
        [Entry(key: title, text: [title, subtitle ?? ""].joined(separator: " "))]
      case .sentence, .cells, .label, .bars, .picture, .quotes, .line, .ruler, .allocation, .heat, .candles, .zones: []
      }
    }
  }

  /// The lines of a day's notes tagged with the run.
  static func notes(_ text: String, of run: Run.ID) -> [String] {
    text.split(separator: "\n").map(String.init).filter { $0.contains("[run/\(run)]") }
  }
}

/// Which event a line is about, when no keyword tells; a model answers in the live eval.
protocol EvalJudge: Sendable {
  func classify(_ line: String, among events: [EvalEvent], noise: [String]) async -> EvalJudgement
}

enum EvalJudgement: Hashable, Sendable, Codable {
  case event(String)
  case noise
  /// About none of them.
  case none
}

/// Whether one day passed, and why not.
struct EvalVerdict: Sendable, Codable {
  let group: String
  let day: Int
  let passed: Bool
  let reasons: [String]
}

/// The rules each day is held to. Lines are tied to events by their keywords first; only a line no keyword
/// ties to anything goes to the judge.
struct EvalScorer: Sendable {
  let scenario: EvalScenario
  let judge: any EvalJudge

  func score(day: Int, before: EvalSnapshot, after: EvalSnapshot, hiddenKey: String?) async -> EvalVerdict {
    var reasons: [String] = []
    if after.mainMessages > 0 { reasons.append("主对话里出现了 \(after.mainMessages) 条消息") }
    let added = after.entries.filter { entry in !before.entries.contains { $0.key == entry.key } }
    for event in scenario.news(on: day) {
      let everywhere = after.entries.map(\.text) + after.notes
      if !everywhere.contains(where: event.isMentioned) { reasons.append("没看到新的「\(event.about)」") }
    }
    switch scenario.group {
    case .quiet:
      if case .news = scenario.days[day].kind {
      } else {
        reasons += await quiet(added: added, before: before, after: after)
      }
    case .repeated:
      reasons += repeated(day: day, after: after, hiddenKey: hiddenKey)
    }
    return EvalVerdict(group: scenario.group.rawValue, day: day + 1, passed: reasons.isEmpty, reasons: reasons)
  }

  /// A day with nothing new: no more lines in the panel than before, none about noise, one note at most.
  private func quiet(added: [EvalSnapshot.Entry], before: EvalSnapshot, after: EvalSnapshot) async -> [String] {
    var reasons: [String] = []
    if after.entries.count > before.entries.count {
      reasons.append("面板从 \(before.entries.count) 条变成 \(after.entries.count) 条")
    }
    for entry in added {
      switch await about(entry.text) {
      case .noise: reasons.append("面板多了噪音「\(entry.text.prefix(40))」")
      case .none: reasons.append("面板多了不相干的「\(entry.text.prefix(40))」")
      case .event: continue
      }
    }
    if after.notes.count > 1 { reasons.append("笔记写了 \(after.notes.count) 行") }
    return reasons
  }

  /// Days after the first: nothing found before is told again, no event has two lines, and what the person
  /// hid does not come back.
  private func repeated(day: Int, after: EvalSnapshot, hiddenKey: String?) -> [String] {
    var reasons: [String] = []
    let known = scenario.known(before: day)
    for line in after.notes {
      for event in known where event.isMentioned(in: line) {
        reasons.append("笔记又记了「\(event.about)」")
      }
    }
    for event in scenario.events {
      let lines = after.entries.filter { event.isMentioned(in: $0.text) && $0.key != hiddenKey }
      if lines.count > 1 { reasons.append("面板里「\(event.about)」有 \(lines.count) 条") }
    }
    if let hidden = scenario.hidden(by: day) {
      for entry in after.entries where entry.key != hiddenKey && hidden.isMentioned(in: entry.text) {
        reasons.append("不想再看的「\(hidden.about)」又放回了面板")
      }
    }
    return reasons
  }

  private func about(_ text: String) async -> EvalJudgement {
    if let event = scenario.events.first(where: { $0.isMentioned(in: text) }) { return .event(event.id) }
    if scenario.noise.contains(where: { text.localizedCaseInsensitiveContains($0) }) { return .noise }
    return await judge.classify(text, among: scenario.events, noise: scenario.noise)
  }
}
