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

  /// The lines one sentence shows, original first. Without a translation every mode shows the original.
  func lines(of sentence: String, translated: String?) -> [String] {
    guard let translated else { return [sentence] }
    switch self {
    case .original: return [sentence]
    case .both: return [sentence, translated]
    case .translation: return [translated]
    }
  }
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

  func lines(_ index: Int, mode: SubtitleMode) -> [String] {
    mode.lines(of: segments[index].text, translated: translated(index))
  }
}
