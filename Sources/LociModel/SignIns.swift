/// A browser on this Mac whose sign-ins the built-in browser can start with. All of them keep cookies the
/// same way, encrypted with a key in the login keychain.
public enum SignInBrowser: String, CaseIterable, Hashable, Codable, Sendable {
  case chrome, edge, brave, arc, chromium, vivaldi, opera

  public var name: String {
    switch self {
    case .chrome: "Chrome"
    case .edge: "Edge"
    case .brave: "Brave"
    case .arc: "Arc"
    case .chromium: "Chromium"
    case .vivaldi: "Vivaldi"
    case .opera: "Opera"
    }
  }
}

/// Where the built-in browser stands with this Mac's other browsers.
public enum SignInChoice: Hashable, Sendable {
  /// Not asked yet: the browser used most lately, offered once.
  case offer(SignInBrowser)
  /// This browser's sign-ins were brought in; they stay in the built-in browser until they expire, and are
  /// brought in again only when the reader asks.
  case using(SignInBrowser)
  /// Asked and turned down; the browser that would be used.
  case declined(SignInBrowser)
  /// No browser on this Mac to take sign-ins from.
  case unavailable
}

public enum SignInFailure: Error, Hashable, Sendable {
  /// The reader did not let Loci use the browser's key.
  case keyRefused
  /// The browser's cookies could not be read or decrypted.
  case unreadable
}

/// The sign-ins of this Mac's other browsers. It belongs to this Mac alone and never crosses to another, so
/// it is handed to the window beside the host rather than served by it.
public protocol BrowserSignIns: Sendable {
  func choice() async -> SignInChoice
  /// Returns `browser`'s cookies, the only time its key is read: macOS may ask whether Loci may use it, and
  /// refusing turns sign-ins down.
  func use(_ browser: SignInBrowser) async throws(SignInFailure) -> [BrowserCookie]
  /// Stops using any browser's sign-ins, and stops offering them.
  func decline() async
}
