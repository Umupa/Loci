import Foundation

/// What a pasted link most likely leads to, told from the address alone, so the right fetcher starts at
/// once. Anything not recognized is read as an article; a page with videos on it is opened in the built-in
/// browser instead.
public enum LinkKind: Hashable, Sendable {
  case video
  case audio
  case paper
  case article

  public init(_ url: URL) {
    let host = (url.host() ?? "").lowercased()
    let path = url.path().lowercased()
    let fileExtension = url.pathExtension.lowercased()
    if Self.videoExtensions.contains(fileExtension) || Self.isVideoPage(host: host, path: path) {
      self = .video
    } else if Self.audioExtensions.contains(fileExtension) || Self.isEpisodePage(host: host, path: path)
      || (Self.matches(host, "podcasts.apple.com") && FollowLink.query(url, "i") != nil)
    {
      self = .audio
    } else if fileExtension == "pdf" || (Self.matches(host, "arxiv.org") && Self.isArxivPaper(path)) {
      self = .paper
    } else {
      self = .article
    }
  }

  private static let videoExtensions: Set = ["mp4", "mov", "m4v", "webm", "mkv"]
  private static let audioExtensions: Set = ["mp3", "m4a", "aac", "wav", "ogg", "opus", "flac"]

  private static func isVideoPage(host: String, path: String) -> Bool {
    if matches(host, "youtube.com") { return path.hasPrefix("/watch") || path.hasPrefix("/live/") }
    if matches(host, "bilibili.com") { return path.hasPrefix("/video/") }
    return matches(host, "youtu.be") || matches(host, "b23.tv") || matches(host, "vimeo.com")
  }

  private static func isEpisodePage(host: String, path: String) -> Bool {
    matches(host, "xiaoyuzhoufm.com") && path.hasPrefix("/episode/")
  }

  private static func isArxivPaper(_ path: String) -> Bool {
    path.hasPrefix("/abs/") || path.hasPrefix("/pdf/")
  }

  private static func matches(_ host: String, _ domain: String) -> Bool {
    host == domain || host.hasSuffix("." + domain)
  }
}
