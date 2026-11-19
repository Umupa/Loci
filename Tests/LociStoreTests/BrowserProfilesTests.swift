import Foundation
import GRDB
import LociModel
import Testing

@testable import LociStore

struct BrowserProfilesTests {
  static let password = Data("peanuts".utf8)
  static let now = Date(timeIntervalSince1970: 1_800_000_000)

  /// A browser's cookie database as Chromium writes it.
  struct FakeCookie {
    var host = ".example.com"
    var name = "session"
    var value = "signed-in"
    var expires: Date? = now.addingTimeInterval(3600)
    var httpOnly = true
  }

  static func withSupport(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "loci-browsers-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
  }

  static func install(
    _ browser: SignInBrowser, in root: URL, profile: String = "Default", lastUsed: String? = nil, version: Int = 24,
    cookies: [FakeCookie], modified: Date = now
  ) throws {
    let folder = root.appending(path: browser.dataFolder)
    let profileFolder = folder.appending(path: profile)
    try FileManager.default.createDirectory(at: profileFolder, withIntermediateDirectories: true)
    if let lastUsed {
      try Data(#"{"profile":{"last_used":"\#(lastUsed)"}}"#.utf8).write(to: folder.appending(path: "Local State"))
    }
    let file = profileFolder.appending(path: "Cookies")
    let cipher = CookieCipher(password: password)
    try DatabaseQueue(path: file.path).write { db in
      try db.execute(sql: "CREATE TABLE meta (key TEXT, value TEXT)")
      try db.execute(sql: "INSERT INTO meta VALUES ('version', ?)", arguments: ["\(version)"])
      try db.execute(
        sql: """
          CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT,
          expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER)
          """)
      for cookie in cookies {
        let hash = version >= 24 ? Data(repeating: 7, count: 32) : Data()
        let expires = cookie.expires.map { Int64(($0.timeIntervalSince1970 + 11_644_473_600) * 1_000_000) } ?? 0
        try db.execute(
          sql: "INSERT INTO cookies VALUES (?, ?, '', ?, '/', ?, 1, ?)",
          arguments: [cookie.host, cookie.name, cipher.seal(cookie.value, domainHash: hash), expires, cookie.httpOnly])
      }
    }
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
  }

  @Test func readsTheDecryptedCookiesOfTheLastUsedProfile() throws {
    try Self.withSupport { root in
      try Self.install(.chrome, in: root, profile: "Profile 1", lastUsed: "Profile 1", cookies: [FakeCookie()])

      let cookies = try BrowserProfiles(applicationSupport: root).cookies(
        of: .chrome, password: Self.password, now: Self.now)

      #expect(
        cookies == [
          BrowserCookie(
            domain: ".example.com", path: "/", name: "session", value: "signed-in", secure: true,
            expires: Timestamp(Self.now.addingTimeInterval(3600)), httpOnly: true)
        ])
    }
  }

  @Test func readsAnOlderDatabaseWhoseValuesHaveNoDomainHash() throws {
    try Self.withSupport { root in
      try Self.install(.brave, in: root, version: 23, cookies: [FakeCookie(value: "old")])

      let cookies = try BrowserProfiles(applicationSupport: root).cookies(
        of: .brave, password: Self.password, now: Self.now)

      #expect(cookies.map(\.value) == ["old"])
    }
  }

  @Test func leavesOutExpiredCookiesAndKeepsOnesThatLastUntilTheBrowserCloses() throws {
    try Self.withSupport { root in
      try Self.install(
        .chrome, in: root,
        cookies: [
          FakeCookie(name: "stale", expires: Self.now.addingTimeInterval(-1)), FakeCookie(name: "tab", expires: nil),
        ])

      let cookies = try BrowserProfiles(applicationSupport: root).cookies(
        of: .chrome, password: Self.password, now: Self.now)

      #expect(cookies.map(\.name) == ["tab"])
      #expect(cookies.first?.expires == nil)
    }
  }

  @Test func aWrongPasswordGivesNoCookies() throws {
    try Self.withSupport { root in
      try Self.install(.chrome, in: root, cookies: [FakeCookie()])

      let cookies = try BrowserProfiles(applicationSupport: root).cookies(
        of: .chrome, password: Data("wrong".utf8), now: Self.now)

      #expect(cookies.isEmpty)
    }
  }

  @Test func offersTheBrowserUsedMostLately() throws {
    try Self.withSupport { root in
      try Self.install(.chrome, in: root, cookies: [], modified: Self.now.addingTimeInterval(-86_400))
      try Self.install(.edge, in: root, cookies: [], modified: Self.now)
      let profiles = BrowserProfiles(applicationSupport: root)

      #expect(profiles.mostRecent() == .edge)
      #expect(profiles.isInstalled(.chrome))
      #expect(!profiles.isInstalled(.arc))
    }
  }

  @Test func aMacWithoutChromiumBrowsersHasNothingToOffer() throws {
    try Self.withSupport { root in
      #expect(BrowserProfiles(applicationSupport: root).mostRecent() == nil)
      #expect(throws: SignInFailure.unreadable) {
        try BrowserProfiles(applicationSupport: root).cookies(of: .chrome, password: Self.password, now: Self.now)
      }
    }
  }

  @Test func theAnswerIsKeptUntilItChanges() throws {
    try Self.withSupport { root in
      let support = Support(root: root)
      #expect(support.signInConsent() == nil)

      try support.save(.using(.chrome))
      #expect(support.signInConsent() == .using(.chrome))

      try support.save(.declined)
      #expect(support.signInConsent() == .declined)
    }
  }
}
