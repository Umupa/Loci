import Foundation
import WebKit

/// A cookie the built-in browser holds, without its value: enough to tell whether a site is signed in.
public struct SiteCookie: Hashable, Sendable {
  public let domain: String
  public let name: String
  /// `nil` for one that lasts until the browser closes.
  public let expires: Date?

  public init(domain: String, name: String, expires: Date?) {
    self.domain = domain
    self.name = name
    self.expires = expires
  }
}

/// The sign-ins of the built-in browser, which also holds those taken from Chrome: which sites have which
/// cookies, when they change, and reading a page with them. Values never leave WebKit.
public protocol SiteSignIns: Sendable {
  /// The cookies on these domains and their subdomains.
  func cookies(on domains: [String]) async -> [SiteCookie]
  /// Yields each time the built-in browser's cookies change.
  func changes() -> AsyncStream<Void>
  /// The text of a page read signed in, sending only GET (`ReadOnlyPage`).
  func read(_ url: URL) async throws(FetchError) -> String
}

extension SiteCookie {
  /// Whether `domain` (`x.com`) covers this cookie's domain (`.x.com`, `api.x.com`).
  public func belongs(to domain: String) -> Bool {
    let own = self.domain.hasPrefix(".") ? String(self.domain.dropFirst()) : self.domain
    return own == domain || own.hasSuffix("." + domain)
  }
}

/// The built-in browser's cookie store: the default WebKit store, which the built-in browser and the article
/// reader share in this process.
public final class BuiltInBrowserSignIns: SiteSignIns {
  private let network: any Network

  /// `network` fetches what is not a web page, such as a PDF a page links to.
  public init(network: any Network) {
    self.network = network
  }

  public func read(_ url: URL) async throws(FetchError) -> String {
    try await SourceTextReader(network: network).read(url, signedIn: true)
  }

  public func cookies(on domains: [String]) async -> [SiteCookie] {
    let all = await MainActor.run { WKWebsiteDataStore.default().httpCookieStore }.allCookies()
    return all.map { SiteCookie(domain: $0.domain, name: $0.name, expires: $0.expiresDate) }
      .filter { cookie in domains.contains { cookie.belongs(to: $0) } }
  }

  public func changes() -> AsyncStream<Void> {
    AsyncStream { continuation in
      Task { @MainActor in
        let watcher = CookieWatcher { continuation.yield() }
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.add(watcher)
        continuation.onTermination = { _ in Task { @MainActor in store.remove(watcher) } }
      }
    }
  }
}

@MainActor
private final class CookieWatcher: NSObject, WKHTTPCookieStoreObserver {
  private let changed: @Sendable () -> Void

  init(changed: @escaping @Sendable () -> Void) {
    self.changed = changed
  }

  nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    changed()
  }
}
