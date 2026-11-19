import Foundation
import GRDB
import LociModel

/// The Chromium browsers installed on this Mac, found by their data in Application Support, and the cookies
/// of the profile each used last.
public struct BrowserProfiles: Sendable {
  private let applicationSupport: URL

  /// `applicationSupport` is `~/Library/Application Support` on a real Mac.
  public init(applicationSupport: URL) {
    self.applicationSupport = applicationSupport
  }

  /// The browser whose cookies changed most lately, which is the one the reader uses.
  public func mostRecent() -> SignInBrowser? {
    SignInBrowser.allCases
      .compactMap { browser in lastUsed(browser).map { (browser, $0) } }
      .max { $0.1 < $1.1 }?.0
  }

  public func isInstalled(_ browser: SignInBrowser) -> Bool {
    lastUsed(browser) != nil
  }

  /// The cookies of the browser's last used profile that have not expired by `now`, decrypted with the
  /// password from its keychain item. Cookies that do not decrypt are left out.
  public func cookies(of browser: SignInBrowser, password: Data, now: Date) throws(SignInFailure) -> [BrowserCookie] {
    guard let file = cookieFile(browser) else { throw .unreadable }
    let copy = FileManager.default.temporaryDirectory.appending(
      path: "loci-cookies-\(UUID())", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: copy) }
    do {
      try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
      for suffix in ["", "-wal", "-journal"] {
        let source = URL(filePath: file.path(percentEncoded: false) + suffix)
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
        try FileManager.default.copyItem(at: source, to: copy.appending(path: "Cookies" + suffix))
      }
      var configuration = Configuration()
      configuration.readonly = true
      let queue = try DatabaseQueue(
        path: copy.appending(path: "Cookies").path(percentEncoded: false), configuration: configuration)
      let cipher = CookieCipher(password: password)
      return try queue.read { db in
        let version = try Int.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'version'") ?? 0
        let rows = try Row.fetchAll(
          db,
          sql: "SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly FROM cookies")
        return rows.compactMap { row in Self.cookie(from: row, cipher: cipher, version: version, now: now) }
      }
    } catch {
      throw .unreadable
    }
  }

  private static func cookie(from row: Row, cipher: CookieCipher, version: Int, now: Date) -> BrowserCookie? {
    let expires: Timestamp?
    let chromeTime: Int64 = row["expires_utc"] ?? 0
    if chromeTime > 0 {
      let date = Date(timeIntervalSince1970: Double(chromeTime) / 1_000_000 - secondsFrom1601To1970)
      guard date > now else { return nil }
      expires = Timestamp(date)
    } else {
      expires = nil
    }
    let plain: String = row["value"] ?? ""
    let sealed: Data = row["encrypted_value"] ?? Data()
    guard let value = plain.isEmpty ? cipher.decrypt(sealed, databaseVersion: version) : plain else { return nil }
    let secure: Int = row["is_secure"] ?? 0
    let httpOnly: Int = row["is_httponly"] ?? 0
    return BrowserCookie(
      domain: row["host_key"] ?? "", path: row["path"] ?? "/", name: row["name"] ?? "", value: value,
      secure: secure != 0, expires: expires, httpOnly: httpOnly != 0)
  }

  /// Chromium counts microseconds from 1601-01-01.
  private static let secondsFrom1601To1970: Double = 11_644_473_600

  private func lastUsed(_ browser: SignInBrowser) -> Date? {
    guard let file = cookieFile(browser) else { return nil }
    let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
    return attributes?[.modificationDate] as? Date
  }

  private func cookieFile(_ browser: SignInBrowser) -> URL? {
    let root = applicationSupport.appending(path: browser.dataFolder, directoryHint: .isDirectory)
    let profile = root.appending(path: lastProfile(in: root), directoryHint: .isDirectory)
    return [profile.appending(path: "Cookies"), profile.appending(path: "Network/Cookies")]
      .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
  }

  /// The profile named in `Local State`, or `Default`.
  private func lastProfile(in root: URL) -> String {
    guard let data = try? Data(contentsOf: root.appending(path: "Local State")),
      let state = try? JSONDecoder().decode(LocalState.self, from: data),
      let name = state.profile?.lastUsed, !name.isEmpty, !name.contains("/")
    else { return "Default" }
    return name
  }

  private struct LocalState: Decodable {
    struct Profile: Decodable {
      let lastUsed: String?

      enum CodingKeys: String, CodingKey {
        case lastUsed = "last_used"
      }
    }

    let profile: Profile?
  }
}

extension SignInBrowser {
  /// Under `~/Library/Application Support`.
  var dataFolder: String {
    switch self {
    case .chrome: "Google/Chrome"
    case .edge: "Microsoft Edge"
    case .brave: "BraveSoftware/Brave-Browser"
    case .arc: "Arc/User Data"
    case .chromium: "Chromium"
    case .vivaldi: "Vivaldi"
    case .opera: "com.operasoftware.Opera"
    }
  }

  /// The login keychain item that holds the password the cookies are encrypted with.
  var keychainService: String { "\(keychainAccount) Safe Storage" }

  var keychainAccount: String {
    switch self {
    case .chrome: "Chrome"
    case .edge: "Microsoft Edge"
    case .brave: "Brave"
    case .arc: "Arc"
    case .chromium: "Chromium"
    case .vivaldi: "Vivaldi"
    case .opera: "Opera"
    }
  }
}
