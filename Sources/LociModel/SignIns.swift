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
  /// Each launch starts with this browser's sign-ins.
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
  /// Starts using `browser` from now on and returns its cookies. The first time, macOS asks whether Loci may
  /// use the browser's key; refusing it turns sign-ins down.
  func use(_ browser: SignInBrowser) async throws(SignInFailure) -> [BrowserCookie]
  /// Stops using any browser's sign-ins, and stops offering them.
  func decline() async
  /// The cookies of the browser in use, read afresh; empty when none is in use.
  func currentCookies() async throws(SignInFailure) -> [BrowserCookie]
}
