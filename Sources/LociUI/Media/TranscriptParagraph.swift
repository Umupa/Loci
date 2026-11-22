import Foundation
import LociModel

/// A stretch of an episode's transcript read as one paragraph: one speaker, one chapter, without a long pause.
struct TranscriptParagraph: Equatable, Identifiable {
  /// The indexes of its sentences in the transcript.
  let sentences: Range<Int>
  /// Numbered from 1; `nil` when speakers were not told apart.
  let speaker: Int?
  let start: Duration

  var id: Int { sentences.lowerBound }

  /// A paragraph that has run this long ends at the next pause.
  static let pauseAfter = Duration.seconds(20)
  /// A silence at least this long is a pause.
  static let pause = Duration.seconds(1)
  /// A paragraph that has run this long ends at the next sentence end, pause or not.
  static let longest = Duration.seconds(75)

  /// A new paragraph starts where the speaker changes or a chapter begins, and, within a long turn, at a
  /// pause or the end of a sentence.
  static func of(_ segments: [Transcript.Segment], chapters: [Outline.Chapter]) -> [TranscriptParagraph] {
    var paragraphs: [TranscriptParagraph] = []
    var first = 0
    var pending = chapters.drop { $0.start <= (segments.first?.start ?? .zero) }
    for index in segments.indices.dropFirst() {
      let segment = segments[index]
      let previous = segments[index - 1]
      let run = previous.end - segments[first].start
      var chapterBegins = false
      while let chapter = pending.first, chapter.start <= segment.start {
        chapterBegins = true
        pending = pending.dropFirst()
      }
      let breaks =
        segment.speaker != previous.speaker || chapterBegins
        || (run >= pauseAfter && segment.start - previous.end >= pause)
        || (run >= longest && endsSentence(previous.text))
      guard breaks else { continue }
      paragraphs.append(TranscriptParagraph(segments, first..<index))
      first = index
    }
    if !segments.isEmpty { paragraphs.append(TranscriptParagraph(segments, first..<segments.count)) }
    return paragraphs
  }

  private init(_ segments: [Transcript.Segment], _ sentences: Range<Int>) {
    self.sentences = sentences
    speaker = segments[sentences.lowerBound].speaker
    start = segments[sentences.lowerBound].start
  }

  /// The translations of its sentences, joined; `nil` without a translation.
  func translation(in transcript: ReadableTranscript) -> String? {
    let lines = sentences.compactMap(transcript.translated)
    return lines.isEmpty ? nil : Self.joined(lines)
  }

  /// Sentences run on with a space between them, but none after Chinese or Japanese.
  static func joined(_ sentences: [String]) -> String {
    var whole = ""
    for sentence in sentences {
      whole += separator(after: whole) + sentence
    }
    return whole
  }

  /// What goes between `text` and the sentence after it.
  static func separator(after text: String) -> String {
    guard let last = text.unicodeScalars.last else { return "" }
    return isCloseSet(last) || last.properties.isWhitespace ? "" : " "
  }

  private static func isCloseSet(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.isIdeographic || (0x3000...0x30FF).contains(scalar.value)
      || (0xFF00...0xFFEF).contains(scalar.value)
  }

  private static func endsSentence(_ text: String) -> Bool {
    guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
    return ".?!。？！…\"”".contains(last)
  }
}
