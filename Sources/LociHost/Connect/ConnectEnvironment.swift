import Foundation
import LociAgents
import LociConnect
import LociMedia
import LociModel
import LociStore

/// What connectors take from the outside world: the network, the loopback the browser comes back to, the
/// keychain, the `gh` signed in on this Mac, the built-in browser's sign-ins, the calendars and reminders of
/// this Mac (written to only for an approval card the person approved), and randomness for PKCE.
public struct ConnectEnvironment: Sendable {
  public let http: any HTTPClient
  public let receiver: any CallbackReceiver
  /// `nil` where there is no keychain: nothing that needs a sign-in can be connected.
  public let vault: (any ConnectorVault)?
  public let githubLogin: @Sendable () async -> GitHubLogin?
  /// Runs `gh` with arguments that only read; anything else is refused before it starts.
  public let githubRead: @Sendable (GitHubRead) async -> GitHubReply
  /// Which websites the built-in browser is signed into, and reading their pages with that sign-in.
  public let sites: any SiteSignIns
  public let personal: any PersonalData
  public let writes: any PersonalWrites
  public let randomBytes: @Sendable (Int) -> Data
  /// How long the browser has to come back.
  public let patience: Duration
  /// Told when the browser came back from a connector's sign-in and the connection is done or has failed, so
  /// the app can come to the front on its Connectors page.
  public let browserReturned: @Sendable (ConnectorID) async -> Void

  public init(
    http: any HTTPClient, receiver: any CallbackReceiver, vault: (any ConnectorVault)?,
    githubLogin: @escaping @Sendable () async -> GitHubLogin?,
    githubRead: @escaping @Sendable (GitHubRead) async -> GitHubReply = { _ in
      .failed("gh is not installed on this Mac")
    },
    sites: any SiteSignIns = NoSites(), personal: any PersonalData = NoPersonalData(),
    writes: any PersonalWrites = NoPersonalWrites(),
    randomBytes: @escaping @Sendable (Int) -> Data = ConnectEnvironment.systemRandom,
    patience: Duration = .seconds(600), browserReturned: @escaping @Sendable (ConnectorID) async -> Void = { _ in }
  ) {
    self.http = http
    self.receiver = receiver
    self.vault = vault
    self.githubLogin = githubLogin
    self.githubRead = githubRead
    self.sites = sites
    self.personal = personal
    self.writes = writes
    self.randomBytes = randomBytes
    self.patience = patience
    self.browserReturned = browserReturned
  }

  /// No network, no keychain: a host that connects nothing, as in previews and most tests.
  public static let disconnected = ConnectEnvironment(
    http: Unreachable(), receiver: Unreachable(), vault: nil, githubLogin: { nil })

  public static func system(
    githubLogin: @escaping @Sendable () async -> GitHubLogin?,
    githubRead: @escaping @Sendable (GitHubRead) async -> GitHubReply,
    browserReturned: @escaping @Sendable (ConnectorID) async -> Void
  ) -> ConnectEnvironment {
    ConnectEnvironment(
      http: URLSessionClient(), receiver: LoopbackReceiver(),
      vault: ConnectorKeychain(serviceName: "com.loci.native.dev.connector"), githubLogin: githubLogin,
      githubRead: githubRead, sites: BuiltInBrowserSignIns(network: SystemNetwork.anonymous()),
      personal: EventKitData(), writes: EventKitWrites(), browserReturned: browserReturned)
  }

  public static let systemRandom: @Sendable (Int) -> Data = { count in
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
  }
}

/// A built-in browser signed into nothing.
public struct NoSites: SiteSignIns {
  public init() {}
  public func cookies(on domains: [String]) async -> [SiteCookie] { [] }
  public func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
  public func read(_ url: URL) async throws(FetchError) -> String {
    throw FetchError(reason: "This Loci has no built-in browser to read signed in with.")
  }
  public func readSource(_ url: URL, on domains: [String]) async throws(FetchError) -> String {
    try await read(url)
  }
}

/// Nothing to reach: every request fails as offline.
private struct Unreachable: HTTPClient, CallbackReceiver {
  func send(_ request: HTTPRequest) async throws(ConnectError) -> HTTPResponse {
    throw .offline("this Loci does not reach the network")
  }

  func open(for service: String) async throws(ConnectError) -> any CallbackWait {
    throw .offline("this Loci cannot listen for the browser")
  }
}
