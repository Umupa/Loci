import Foundation
import LociModel

/// Which words of each sentence show, in the transcript and over the picture.
enum SubtitleMode: String, CaseIterable, Codable {
  /// Where the mode is remembered; videos, podcasts and articles share it.
  static let key = "subtitleMode"

  case original
  /// The original with the translation under it.
  case both
  case translation

  var name: LocalizedStringResource {
    switch self {
    case .original: .loci("subtitles.original")
    case .both: .loci("subtitles.both")
    case .translation: .loci("subtitles.translation")
    }
  }

  /// The lines one sentence shows, in `order` when both do. Without a translation every mode shows the
  /// original.
  func lines(of sentence: String, translated: String?, order: SubtitleStyle.BilingualOrder) -> [SubtitleLine] {
    let original = SubtitleLine(text: sentence, translated: false)
    guard let translated else { return [original] }
    let translation = SubtitleLine(text: translated, translated: true)
    switch self {
    case .original: return [original]
    case .both: return order == .translationAbove ? [translation, original] : [original, translation]
    case .translation: return [translation]
    }
  }
}

/// One line of a sentence as it shows: the original's words or the translation's.
struct SubtitleLine: Equatable {
  let text: String
  let translated: Bool
}

/// A transcript with the translation it is read with, sentence by sentence.
struct ReadableTranscript: Equatable {
  let transcript: Transcript
  /// One line per segment, or `nil`.
  let translation: Translation?

  /// Picks the translation into the reader's language among those that fit; the first that fits otherwise.
  init(transcript: Transcript, translations: [Translation], language: String?) {
    self.transcript = transcript
    let fitting = translations.filter { $0.fits(transcript) && $0.language != transcript.language }
    let preferred = language.flatMap { language in
      fitting.first { $0.language == language || language.hasPrefix($0.language + "-") }
    }
    translation = preferred ?? fitting.first
  }

  var segments: [Transcript.Segment] { transcript.segments }

  func translated(_ index: Int) -> String? {
    guard let lines = translation?.lines, lines.indices.contains(index) else { return nil }
    return lines[index]
  }

  func lines(_ index: Int, mode: SubtitleMode, order: SubtitleStyle.BilingualOrder) -> [SubtitleLine] {
    mode.lines(of: segments[index].text, translated: translated(index), order: order)
  }
}

extension ReadableTranscript {
  /// The sentences chosen, as a stretch of time and their words.
  func passage(_ range: NSRange, of item: EntityID) -> (locator: Locator, excerpt: String)? {
    let last = range.location + max(range.length, 1) - 1
    guard segments.indices.contains(range.location), segments.indices.contains(last),
      let span = try? TimeSpan(start: segments[range.location].start, end: segments[last].end)
    else { return nil }
    return (.item(item, .time(span)), TranscriptParagraph.joined(segments[range.location...last].map(\.text)))
  }
}
