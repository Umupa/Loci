import Foundation
import LociModel
import LociStore

/// This Mac's other browsers, for the built-in browser to start signed in. The reader's answer is kept in
/// Loci's Application Support folder; the cookies are read afresh each time and never written anywhere.
public actor LocalSignIns: BrowserSignIns {
  private let profiles: BrowserProfiles
  private let keys: any BrowserKeys
  private let support: Support
  private let now: @Sendable () -> Date

  public init(
    applicationSupport: URL, support: URL, keys: any BrowserKeys = LoginKeychain(),
    now: @escaping @Sendable () -> Date = { .now }
  ) {
    profiles = BrowserProfiles(applicationSupport: applicationSupport)
    self.support = Support(root: support)
    self.keys = keys
    self.now = now
  }

  /// The browsers and the answer on this Mac.
  public static func onThisMac() -> LocalSignIns {
    LocalSignIns(
      applicationSupport: .applicationSupportDirectory,
      support: URL.applicationSupportDirectory.appending(path: "Loci", directoryHint: .isDirectory))
  }

  public func choice() -> SignInChoice {
    switch support.signInConsent() {
    case .using(let browser) where profiles.isInstalled(browser):
      return .using(browser)
    case .using, .declined:
      return profiles.mostRecent().map(SignInChoice.declined) ?? .unavailable
    case nil:
      return profiles.mostRecent().map(SignInChoice.offer) ?? .unavailable
    }
  }

  public func use(_ browser: SignInBrowser) throws(SignInFailure) -> [BrowserCookie] {
    let cookies: [BrowserCookie]
    do {
      cookies = try profiles.cookies(of: browser, password: try keys.password(for: browser), now: now())
    } catch .keyRefused {
      decline()
      throw .keyRefused
    }
    try? support.save(.using(browser))
    return cookies
  }

  public func decline() {
    try? support.save(.declined)
  }

  public func currentCookies() throws(SignInFailure) -> [BrowserCookie] {
    guard case .using(let browser) = choice() else { return [] }
    return try profiles.cookies(of: browser, password: try keys.password(for: browser), now: now())
  }
}
