import Foundation
import LociConnect
import LociModel
import LociStore

/// What a repair of a source and a panel's pick of new entries are asked.
extension Prompts {
  /// The most characters of one failed response shown to a repair.
  static let responseShown = 4000
  /// The most entries a panel is offered in one run.
  static let entriesOffered = 30

  /// The source as it is, why it broke, and the responses its `parse` failed on, marked as content from
  /// outside.
  func repair(_ source: DataSource, broken: SourceSnapshot, failed samples: [SourceSample], timeZone: TimeZone)
    -> String
  {
    let since = broken.breakage.map { Self.moment($0.since, in: timeZone) } ?? "a while"
    let window = source.window.map { " --between \($0.from)-\($0.to)" + ($0.weekdays ? " --weekdays" : "") } ?? ""
    let shown = samples.map { sample in
      let responses = sample.responses.enumerated().map { index, response in
        let text =
          response.text.count > Self.responseShown
          ? String(response.text.prefix(Self.responseShown))
            + "\n…(\(response.text.count - Self.responseShown) more characters cut)"
          : response.text
        return "responses[\(index)] \(response.url.absoluteString), status \(response.status):\n\(text)"
      }
      return "Fetched \(Self.moment(sample.at, in: timeZone)):\n\n"
        + ExternalContent.wrap(responses.joined(separator: "\n\n"), from: source.name, tool: "fetch")
    }
    return
      repair
      .replacing("{{name}}", with: source.name)
      .replacing("{{title}}", with: source.title)
      .replacing("{{every}}", with: source.every.description)
      .replacing("{{window}}", with: window)
      .replacing("{{failures}}", with: String(broken.breakage?.failures ?? SourceSnapshot.brokenAfter))
      .replacing("{{since}}", with: since)
      .replacing("{{problems}}", with: (broken.breakage?.problems ?? []).map { "- \($0)" }.joined(separator: "\n"))
      .replacing("{{script}}", with: source.script)
      .replacing("{{samples}}", with: shown.isEmpty ? "(none were kept)" : shown.joined(separator: "\n\n"))
  }

  /// The new entries of the source a panel follows, by id, marked as content from outside.
  func feed(_ panel: Panel, source: String, entries: [SeenEntry], timeZone: TimeZone) -> String {
    let lines = entries.map { seen in
      let entry = seen.entry
      let when = entry.at.map { " (\(Self.moment($0, in: timeZone)))" } ?? ""
      let note = entry.note.map { " — \($0)" } ?? ""
      return "- [\(entry.id)] \(entry.title)\(note)\(when)"
    }
    let listed =
      lines.isEmpty
      ? "(nothing new; keep none and say so)"
      : ExternalContent.wrap(lines.joined(separator: "\n"), from: source, tool: "entries")
    return
      feed
      .replacing("{{name}}", with: panel.name)
      .replacing("{{follow}}", with: panel.follow)
      .replacing("{{source}}", with: source)
      .replacing("{{entries}}", with: listed)
  }

  private static func moment(_ moment: Timestamp, in timeZone: TimeZone) -> String {
    "\(Day(containing: moment, in: timeZone)) \(TimeOfDay(of: moment, in: timeZone))"
  }
}
