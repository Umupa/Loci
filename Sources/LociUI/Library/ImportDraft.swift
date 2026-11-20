import Foundation
import LociModel

/// The import panel's choices while it is open. The site's subtitles and recognition both make the transcript,
/// so turning one on turns the other off; turning the subtitles off turns recognition on. A site without
/// subtitles of its own leaves recognition on.
struct ImportDraft: Equatable {
  var keeping: ImportChoice.Keeping
  var quality: ImportChoice.Quality
  private(set) var subtitles: Bool
  var subtitleLanguage: String?
  private(set) var recognizes: Bool
  var recognizing: ImportChoice.Recognizing
  var translates: Bool
  var translating: ImportChoice.Translating
  /// The subtitle languages the site has.
  let offered: [String]
  /// What the last choice said about subtitles, kept when this one has none to choose.
  private let usedSubtitles: Bool

  init(
    _ choice: ImportChoice, offered: [String] = [], spoken: String? = nil, speechModel: SpeechModel,
    readerLanguage: String
  ) {
    keeping = choice.keeping
    quality = choice.quality
    self.offered = offered
    usedSubtitles = choice.siteSubtitles
    subtitles = choice.siteSubtitles && !offered.isEmpty
    subtitleLanguage = choice.subtitleLanguage.flatMap { offered.contains($0) ? $0 : nil } ?? spoken ?? offered.first
    recognizes = offered.isEmpty || (!subtitles && choice.recognition != nil)
    recognizing = choice.recognition ?? ImportChoice.Recognizing(language: nil, model: speechModel)
    translates = choice.translation != nil
    translating = choice.translation ?? ImportChoice.Translating(language: readerLanguage, runtime: nil)
  }

  mutating func useSubtitles(_ on: Bool) {
    subtitles = on
    recognizes = !on
  }

  mutating func recognize(_ on: Bool) {
    recognizes = on
    if on { subtitles = false }
  }

  /// What is taken in: recognition is kept as the way to a transcript when the site's subtitles fail.
  var choice: ImportChoice {
    let transcribed = recognizes || subtitles
    return ImportChoice(
      keeping: keeping, quality: quality, siteSubtitles: offered.isEmpty ? usedSubtitles : subtitles,
      subtitleLanguage: subtitleLanguage, recognition: transcribed ? recognizing : nil,
      translation: translates ? translating : nil)
  }

  /// About how many bytes taking it in uses: the media kept on this Mac and a speech model still to download.
  /// `nil` when the media's size is not known.
  func bytes(sizes: [ImportChoice.Quality: Int64]?, isAudio: Bool, missingModel: Bool) -> Int64? {
    let model = recognizes && missingModel ? recognizing.model.size : 0
    guard keeping == .local, let sizes else { return model }
    guard let media = sizes[isAudio ? .audio : quality] else { return nil }
    return media + model
  }
}
