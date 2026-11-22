import Foundation
import LociModel

/// What the transcript agent is asked when picking key points. A source that fits in one turn is picked from
/// directly; a longer one gives candidates piece by piece, and a last turn picks among them.
enum KeyPointPrompts {
  /// One turn over the whole source, or over one `piece` of it for candidates.
  static func pick(
    _ lines: [String], of source: KeyPointUnits, title: String, count: ClosedRange<Int>, for reader: KeyPointReader,
    piece: (number: Int, of: Int)? = nil
  ) -> String {
    let wanted =
      piece == nil
      ? "Pick \(range(count)) \(source.noun) most worth the reader's time"
      : "This is part \(piece?.number ?? 1) of \(piece?.of ?? 1). Suggest up to \(count.upperBound) \(source.noun) "
        + "in this part worth the reader's time; a later turn picks among all parts"
    return """
      Below is \(source.described) "\(title)", \(source.layout)

      \(wanted). \(source.rule)

      \(voice(reader))

      Return only one JSON object, no prose around it: {"keyPoints": [\(source.shape)]}

      \(source.heading):
      \(lines.joined(separator: "\n"))
      """
  }

  /// The last turn of a long source: picks among the candidates the pieces gave.
  static func choose(
    among candidates: [KeyPoint], of source: KeyPointUnits, title: String, count: ClosedRange<Int>,
    for reader: KeyPointReader
  ) -> String {
    let listed = candidates.map { "\(source.label($0.place)) \($0.title): \($0.reason)" }.joined(separator: "\n")
    return """
      These are candidate key points of \(source.described) "\(title)", each with its place and why it was \
      suggested.

      Pick \(range(count)) of them, the ones most worth the reader's time, keeping each one's place exactly as \
      given. Rewrite the title and the reason of each one you keep.

      \(voice(reader))

      Return only one JSON object, no prose around it: {"keyPoints": [\(source.shape)]}

      The candidates:
      \(listed)
      """
  }

  private static func voice(_ reader: KeyPointReader) -> String {
    var lines = [
      "Write titles and reasons in the language with BCP 47 tag `\(reader.language)`. You are Loci, the "
        + "reader's companion who lives in their library; each reason is one sentence you say to them, "
        + "\"you\", on why this is worth their time, tied to what they learn for when it fits. Keep titles short. "
        + "Do not describe the material from outside (\"this part discusses\")."
    ]
    let profile = reader.profile.trimmingCharacters(in: .whitespacesAndNewlines)
    if !profile.isEmpty { lines.append("About the reader, from their USER.md:\n\(profile)") }
    if let why = reader.why?.trimmingCharacters(in: .whitespacesAndNewlines), !why.isEmpty {
      lines.append("When they took this in, they wrote why: \"\(why)\"")
    }
    return lines.joined(separator: "\n\n")
  }

  private static func range(_ count: ClosedRange<Int>) -> String {
    count.lowerBound == count.upperBound ? "exactly \(count.lowerBound)" : "\(count.lowerBound) to \(count.upperBound)"
  }
}

/// What a source is cut into for picking: the sentences of a transcript or the passages of an article.
enum KeyPointUnits: Sendable {
  case sentences([Transcript.Segment])
  case passages([String])

  var count: Int {
    switch self {
    case .sentences(let segments): segments.count
    case .passages(let passages): passages.count
    }
  }

  var noun: String {
    switch self {
    case .sentences: "stretches"
    case .passages: "paragraphs"
    }
  }

  var described: String {
    switch self {
    case .sentences: "the transcript of"
    case .passages: "the article"
    }
  }

  var layout: String {
    switch self {
    case .sentences: "one sentence per line with its start and end in seconds."
    case .passages: "one passage per line with its number in brackets."
    }
  }

  var heading: String {
    switch self {
    case .sentences: "The transcript"
    case .passages: "The article"
    }
  }

  var rule: String {
    switch self {
    case .sentences:
      "Each runs from a sentence's start to a later sentence's end, usually half a minute to two minutes, and "
        + "they do not overlap."
    case .passages: "Each is one paragraph, named by its number; headings are not key points."
    }
  }

  var shape: String {
    switch self {
    case .sentences: #"{"start": 0.0, "end": 0.0, "title": "…", "reason": "…"}"#
    case .passages: #"{"passage": 1, "title": "…", "reason": "…"}"#
    }
  }

  /// The lines of units `range`, as the agent reads them.
  func lines(_ range: Range<Int>) -> [String] {
    switch self {
    case .sentences(let segments):
      segments[range].map { "[\(TranscriptPrompts.seconds($0.start))-\(TranscriptPrompts.seconds($0.end))] \($0.text)" }
    case .passages(let passages):
      range.map { "[\($0 + 1)] " + passages[$0].replacing("\n", with: " ") }
    }
  }

  func label(_ place: KeyPoint.Place) -> String {
    switch place {
    case .time(let span):
      "[\(TranscriptPrompts.seconds(span.start))-\(TranscriptPrompts.seconds(span.end ?? span.start))]"
    case .passage(let passage): "[\(passage.number)]"
    }
  }
}
