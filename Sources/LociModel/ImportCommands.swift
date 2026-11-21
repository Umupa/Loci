import Foundation

/// Reads what is behind a video or episode link before it is taken in: the item already in the library
/// for that link, or the title, cover and sizes to choose from.
public struct ProbeLink: Command {
  public static let name = "library.probeLink"
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> LinkProbe {
    try await handler.probeLink(self)
  }
}

/// The last way something was taken in, or the first default before any.
public struct ReadImportChoice: Command {
  public static let name = "library.importChoice"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> ImportChoice {
    try await handler.importChoice()
  }
}

/// What a link leads to, as far as taking it in goes.
public enum LinkProbe: Hashable, Codable, Sendable {
  /// The library has an item from this link already.
  case saved(Item)
  case media(MediaPreview)
}

/// A video or episode as the site describes it.
public struct MediaPreview: Hashable, Codable, Sendable {
  public let title: String
  /// The channel or show.
  public let site: String?
  public let duration: Duration?
  public let cover: Data?
  /// Nothing to see, only to listen to.
  public let isAudio: Bool
  /// About how many bytes each quality takes; a quality the site does not offer is missing.
  public let sizes: [ImportChoice.Quality: Int64]
  /// The languages the site has its own subtitles in, as the site names them; empty when it has none.
  public let subtitles: [String]
  /// The one in the spoken language, used unless another is chosen.
  public let spokenSubtitles: String?

  public init(
    title: String, site: String?, duration: Duration?, cover: Data?, isAudio: Bool,
    sizes: [ImportChoice.Quality: Int64], subtitles: [String], spokenSubtitles: String?
  ) {
    self.title = title
    self.site = site
    self.duration = duration
    self.cover = cover
    self.isAudio = isAudio
    self.sizes = sizes
    self.subtitles = subtitles
    self.spokenSubtitles = spokenSubtitles
  }
}
