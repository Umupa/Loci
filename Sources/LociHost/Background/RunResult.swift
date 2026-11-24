import Foundation
import LociModel

/// What came of a run's turn.
enum RunResult: Equatable {
  /// The reply after the last tool, and the sources the run read.
  case finished(reply: String, sources: [String])
  /// `again` when trying once more might go better: the agent failed partway, not that it could not start.
  case failed(String, again: Bool)
  /// Stopped by the app: the panel it was for was removed, or the app is quitting.
  case stopped

  init(of turn: [Message]) {
    var reply: [String] = []
    var sources: [String] = []
    for message in turn {
      switch message.body {
      case .ended(.failed(let reason)):
        self = .failed(reason, again: true)
        return
      case .ended(.unstarted(let provider, .notInstalled)):
        self = .failed("\(provider.rawValue) is not installed", again: false)
        return
      case .ended(.unstarted(let provider, .wouldNotStart)):
        self = .failed("\(provider.rawValue) would not start", again: false)
        return
      case .ended(.interrupted):
        self = .stopped
        return
      case .tool(let tool):
        reply = []
        for source in Self.sources(in: tool.subject ?? "") where !sources.contains(source) { sources.append(source) }
      case .reply(let text):
        reply.append(text)
      default:
        continue
      }
    }
    self = .finished(reply: reply.joined().trimmingCharacters(in: .whitespacesAndNewlines), sources: sources)
  }

  /// The web links in what a tool worked on, such as `"$LOCI" read https://…`.
  static func sources(in subject: String) -> [String] {
    subject.matches(of: /https?:\/\/[^\s"'<>`)]+/).map { String($0.output) }
  }

  /// The last sentence of a reply: what the run is summed up by. `。！？` and a line end a sentence; `.!?`
  /// only before a space, so `v0.9.0` stays whole.
  static func summary(of reply: String) -> String {
    let text = Array(reply.trimmingCharacters(in: .whitespacesAndNewlines))
    var sentences: [String] = []
    var sentence = ""
    for (index, character) in text.enumerated() {
      sentence.append(character)
      let next = index + 1 < text.count ? text[index + 1] : " "
      let ends = "。！？\n".contains(character) || (".!?".contains(character) && next.isWhitespace)
      if ends {
        sentences.append(sentence)
        sentence = ""
      }
    }
    sentences.append(sentence)
    let last = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.last { $0.count > 1 }
    return last ?? String(text)
  }
}

/// The text of `agent/runs/<day>/<id>.md`, written as the run goes on.
enum RunRecord {
  static func header(_ run: Run, events: [String], tries: Int, in timeZone: TimeZone) -> String {
    let started = "\(Day(containing: run.startedAt, in: timeZone)) \(TimeOfDay(of: run.startedAt, in: timeZone))"
    return "# \(started) · run \(run.id)\n\nevents:\n" + events.map { "- \($0)\n" }.joined()
      + "connectors: none\n"
  }

  static func found(_ reply: String, summary: String, sources: [String], tries: Int) -> String {
    let read = sources.isEmpty ? "sources: none\n" : "sources:\n" + sources.map { "- \($0)\n" }.joined()
    return "\ntries: \(tries)\n\(read)\n## Found\n\n\(reply)\n\n## Summary\n\n\(summary)\n"
  }

  static func failed(try number: Int, _ reason: String, final: Bool) -> String {
    "\n## Try \(number) failed\n\n\(reason)\n" + (final ? "\nGiven up after \(number) tries.\n" : "")
  }
}
