/// Why fetching a video or episode failed, sorted by what the reader can do about it.
public struct MediaError: Error, Hashable, Sendable {
  public let kind: Kind
  /// In the words of the program or site that said so.
  public let reason: String

  public init(_ kind: Kind, reason: String) {
    self.kind = kind
    self.reason = reason
  }

  public enum Kind: Hashable, Sendable {
    /// The site wants a signed-in visitor.
    case needsLogin
    /// yt-dlp no longer understands the site; a newer one usually does.
    case outdated
    /// The site's player needs a JavaScript runtime, which QuickJS provides.
    case needsJavaScript
    /// The browser's cookies could not be read, often because macOS did not allow it.
    case cookiesUnreadable
    /// Gone, private, or not there; trying again will not help.
    case unavailable
    /// The site could not be reached: no connection, a refused or timed-out request, a broken proxy.
    case network
    /// Anything else.
    case other
  }

  /// Sorts what yt-dlp wrote to standard error.
  static func fromYtDlp(_ diagnostics: String) -> MediaError {
    let lines = diagnostics.split(whereSeparator: \.isNewline).map(String.init)
    let said = lines.last { $0.hasPrefix("ERROR:") } ?? lines.last ?? "yt-dlp failed"
    let reason = said.hasPrefix("ERROR: ") ? String(said.dropFirst(7)) : said
    let text = diagnostics.lowercased()
    let kind: Kind
    if ["javascript runtime", "js runtime", "n challenge", "signature solving"].contains(where: text.contains) {
      kind = .needsJavaScript
    } else if text.contains("cookie")
      && ["could not", "failed to", "operation not permitted", "permission", "unable to"].contains(where: text.contains)
    {
      kind = .cookiesUnreadable
    } else if [
      "sign in", "login", "log in", "members-only", "confirm your age", "cookies-from-browser", "premium",
      "fresh cookies",
    ]
    .contains(where: text.contains) {
      kind = .needsLogin
    } else if [
      "video unavailable", "video is unavailable", "has been removed", "private video", "does not exist",
      "http error 404", "unsupported url", "available in your country", "has been terminated",
    ]
    .contains(where: text.contains) {
      kind = .unavailable
    } else if ["unable to extract", "please report this issue", "nsig extraction failed"]
      .contains(where: text.contains)
    {
      kind = .outdated
    } else if [
      "unable to download webpage", "timed out", "connection refused", "connection reset", "network is unreachable",
      "name resolution", "nodename nor servname", "failed to resolve", "ssl:", "urlopen error",
    ]
    .contains(where: text.contains) {
      kind = .network
    } else {
      kind = .other
    }
    return MediaError(kind, reason: reason)
  }
}
