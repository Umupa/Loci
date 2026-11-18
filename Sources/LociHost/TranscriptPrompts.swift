import Foundation
import LociModel

/// What the transcript agent is asked. Each prompt ends with the exact JSON shape wanted.
enum TranscriptPrompts {
  static func translation(of lines: [String], into language: String) -> String {
    """
    Translate each line of this transcript into the language with BCP 47 tag `\(language)`. Translate the \
    meaning naturally, keep technical terms recognizable, and keep one output line for each input line, in the \
    same order: the answer has exactly \(lines.count) lines, none of them empty.

    Return only one JSON object, no prose around it: {"lines": ["…", …]}

    The lines:
    \(json(["lines": lines]))
    """
  }

  static func outline(of segments: [Transcript.Segment], title: String, piece: Int, of pieces: Int) -> String {
    let from = seconds(segments.first?.start ?? .zero)
    let to = seconds(segments.last?.end ?? .zero)
    let part = pieces > 1 ? " This is part \(piece) of \(pieces), from \(from) to \(to) seconds." : ""
    let lines = segments.map { "[\(seconds($0.start))-\(seconds($0.end))] \($0.text)" }.joined(separator: "\n")
    return """
      Below is the transcript of "\(title)", one sentence per line with its start and end in seconds.\(part)

      1. Split it into chapters where the topic changes: each starts at a sentence's start time, between \
      \(from) and \(to), in time order, with a short title.
      2. Pick the highlights: the few stretches most worth hearing for an engineer learning the subject, each \
      from a sentence's start to a later sentence's end, with a short title and one sentence on why it is worth \
      hearing.

      Write titles and reasons in the transcript's own language. Return only one JSON object, no prose around \
      it: {"chapters": [{"start": 0.0, "title": "…"}], "highlights": [{"start": 0.0, "end": 0.0, "title": "…", \
      "reason": "…"}]}

      The transcript:
      \(lines)
      """
  }

  static func seconds(_ duration: Duration) -> String {
    String(format: "%.1f", duration.inSeconds)
  }

  private static func json(_ value: [String: [String]]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
  }
}

/// Why an agent's answer cannot be used, in words that go into the error when asking again did not help.
struct TranscriptAnswerError: Error {
  let reason: String

  init(_ reason: String) {
    self.reason = reason
  }
}

/// Reads and checks the transcript agent's answers.
enum TranscriptAnswers {
  /// The translated lines, exactly `count` of them, none empty.
  static func lines(in reply: String, count: Int) throws(TranscriptAnswerError) -> [String] {
    struct Lines: Decodable { let lines: [String] }
    let lines = try decode(Lines.self, from: reply).lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard lines.count == count else {
      throw TranscriptAnswerError("\(lines.count) lines came back for \(count)")
    }
    guard !lines.contains(where: \.isEmpty) else { throw TranscriptAnswerError("a line came back empty") }
    return lines
  }

  /// Chapters in order within the piece, from `start` to `end`, and highlights within the whole `duration`.
  static func outline(
    in reply: String, from start: Duration, to end: Duration, duration: Duration
  ) throws(TranscriptAnswerError) -> Outline {
    struct Chapter: Decodable {
      let start: Double
      let title: String
    }
    struct Highlight: Decodable {
      let start: Double
      let end: Double
      let title: String
      let reason: String
    }
    struct Answer: Decodable {
      let chapters: [Chapter]
      let highlights: [Highlight]
    }
    let answer = try decode(Answer.self, from: reply)
    let slack = Duration.seconds(1)
    do {
      let chapters = try answer.chapters.map { chapter throws -> Outline.Chapter in
        let at = time(chapter.start)
        guard at >= start - slack, at <= end else {
          throw TranscriptAnswerError("a chapter starts at \(chapter.start)s, outside this part")
        }
        return try Outline.Chapter(start: max(at, .zero), title: chapter.title)
      }
      let highlights = try answer.highlights.map { highlight throws -> Outline.Highlight in
        guard highlight.end <= duration.inSeconds + 1 else {
          throw TranscriptAnswerError("a highlight ends at \(highlight.end)s, after the end")
        }
        return try Outline.Highlight(
          span: try TimeSpan(start: time(highlight.start), end: time(highlight.end)), title: highlight.title,
          reason: highlight.reason)
      }
      return try Outline(chapters: chapters, highlights: highlights)
    } catch let error as TranscriptAnswerError {
      throw error
    } catch {
      throw TranscriptAnswerError("\(error)")
    }
  }

  /// The JSON object in a reply, which may have words or a code fence around it.
  private static func decode<Value: Decodable>(_ type: Value.Type, from reply: String) throws(TranscriptAnswerError)
    -> Value
  {
    guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close else {
      throw TranscriptAnswerError("the answer has no JSON object in it")
    }
    do {
      return try JSONDecoder().decode(type, from: Data(reply[open...close].utf8))
    } catch {
      throw TranscriptAnswerError("the JSON is not in the asked shape")
    }
  }

  private static func time(_ seconds: Double) -> Duration {
    .milliseconds(Int((seconds * 1000).rounded()))
  }
}

extension Duration {
  var inSeconds: Double {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
