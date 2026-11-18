import Foundation
import LociModel

/// What goes in front of each message Loci is sent: the things that change while a session goes on.
/// `AGENTS.md` is read once when a session starts, so anything that can change since lives here.
struct TurnContext: Sendable {
  let now: Timestamp
  let timeZone: TimeZone
  let conversation: ConversationRef
  /// What happened in the library since the person last said something here, one fact a line.
  let happenings: [String]
  /// What the person has open, in a line.
  let open: String?
  /// Files shown once and again whenever they change.
  let files: [ShownFile]

  /// The most happenings listed; the rest are counted.
  static let happeningLimit = 20

  /// A file whose text is shown, cut to its last `keep` characters.
  struct ShownFile: Sendable {
    let path: String
    let text: String
    let keep: Int?
  }

  /// The prefix, and the files' fingerprints to remember as shown. A file is left out when `shown` holds
  /// its fingerprint already.
  func prefix(shown: [String: String]) -> (text: String, shown: [String: String]) {
    var lines = ["<loci-context>", "Now: \(Self.moment(now, in: timeZone))"]
    lines.append("Conversation: \(Self.name(of: conversation)). Tag your notes [\(Self.tag(of: conversation))].")
    if !happenings.isEmpty {
      lines.append("Since we last talked here:")
      lines += happenings.suffix(Self.happeningLimit)
      if happenings.count > Self.happeningLimit {
        lines.append("…and \(happenings.count - Self.happeningLimit) earlier.")
      }
    }
    if let open { lines.append("Open: " + open) }
    var remembered = shown
    for file in files {
      let fingerprint = Fingerprint.of(file.text)
      guard shown[file.path] != fingerprint else { continue }
      remembered[file.path] = fingerprint
      lines.append("")
      lines.append("\(file.path):")
      lines.append(Self.cut(file))
    }
    lines.append("</loci-context>")
    return (lines.joined(separator: "\n") + "\n\n", remembered)
  }

  private static func cut(_ file: ShownFile) -> String {
    let text = file.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let keep = file.keep, text.count > keep else { return text.isEmpty ? "(empty)" : text }
    return "…" + text.suffix(keep)
      + "\n(Earlier notes are in \(file.path); move what is worth keeping into MEMORY.md.)"
  }

  /// `Wednesday 2026-11-18 09:12, morning (Asia/Shanghai)`.
  static func moment(_ now: Timestamp, in timeZone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let weekday = calendar.component(.weekday, from: now.date)
    let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    let time = TimeOfDay(of: now, in: timeZone)
    return "\(names[(weekday - 1) % 7]) \(Day(containing: now, in: timeZone)) \(time), \(part(of: time))"
      + " (\(timeZone.identifier))"
  }

  static func part(of time: TimeOfDay) -> String {
    switch time.hour {
    case 5..<12: "morning"
    case 12..<18: "afternoon"
    case 18..<23: "evening"
    default: "late night"
    }
  }

  static func name(of conversation: ConversationRef) -> String {
    switch conversation {
    case .main: "main"
    case .item(let item): "on the item library/\(item)"
    }
  }

  static func tag(of conversation: ConversationRef) -> String {
    switch conversation {
    case .main: NoteSource.main.tag
    case .item(let item): NoteSource.item(item, title: nil).tag
    }
  }
}
