/// How one video, episode or media file is taken into the library: kept on this Mac or watched online,
/// at what quality, where its transcript comes from, and whether it is translated. The import panel starts
/// from the last one made; `loci save` uses it as it is.
public struct ImportChoice: Hashable, Codable, Sendable {
  public var keeping: Keeping
  /// Only for a video kept on this Mac.
  public var quality: Quality
  /// The site's own subtitles are used when it has them.
  public var siteSubtitles: Bool
  /// The language of the site's subtitles to prefer; `nil` takes the spoken one.
  public var subtitleLanguage: String?
  /// How speech is recognized when the site's subtitles are not used; `nil` makes no transcript then.
  public var recognition: Recognizing?
  /// `nil` leaves the transcript untranslated.
  public var translation: Translating?

  public init(
    keeping: Keeping, quality: Quality, siteSubtitles: Bool, subtitleLanguage: String? = nil,
    recognition: Recognizing?, translation: Translating?
  ) {
    self.keeping = keeping
    self.quality = quality
    self.siteSubtitles = siteSubtitles
    self.subtitleLanguage = subtitleLanguage
    self.recognition = recognition
    self.translation = translation
  }

  /// The choice before any was made: kept on this Mac at 720p, the site's subtitles when it has them and
  /// recognition otherwise, translated into the reader's language by whatever Loci runs on.
  public static func first(readerLanguage: String, speechModel: SpeechModel) -> ImportChoice {
    ImportChoice(
      keeping: .local, quality: .hd720, siteSubtitles: true,
      recognition: Recognizing(language: nil, model: speechModel),
      translation: Translating(language: readerLanguage, runtime: nil))
  }

  public enum Keeping: String, Hashable, Codable, Sendable {
    /// The media file is downloaded into the item's folder.
    case local
    /// Played from the site; nothing but the transcript and what is made from it is kept.
    case online
  }

  public enum Quality: String, CaseIterable, Hashable, Codable, Sendable {
    case hd1080
    case hd720
    /// Only the sound of a video.
    case audio

    /// The tallest picture downloaded; `nil` for sound only.
    public var height: Int? {
      switch self {
      case .hd1080: 1080
      case .hd720: 720
      case .audio: nil
      }
    }
  }

  public struct Recognizing: Hashable, Codable, Sendable {
    /// A BCP 47 tag; `nil` lets recognition tell.
    public var language: String?
    public var model: SpeechModel

    public init(language: String?, model: SpeechModel) {
      self.language = language
      self.model = model
    }
  }

  public struct Translating: Hashable, Codable, Sendable {
    /// A BCP 47 tag.
    public var language: String
    /// `nil` runs on whatever Loci runs on.
    public var runtime: Runtime?

    public init(language: String, runtime: Runtime?) {
      self.language = language
      self.runtime = runtime
    }
  }
}
