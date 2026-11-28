import Foundation
import LociHost
import LociModel
import LociStore
import Testing

struct SignInScenarioTests {
  struct Keys: BrowserKeys {
    var refused = false

    func password(for browser: SignInBrowser) throws(SignInFailure) -> Data {
      if refused { throw .keyRefused }
      return Data("peanuts".utf8)
    }
  }

  static func withMac(_ body: (URL, URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "loci-sign-ins-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root.appending(path: "Application Support"), root.appending(path: "Loci"))
  }

  /// Chrome's cookie file, enough for Loci to know Chrome is there.
  static func installChrome(in applicationSupport: URL) throws {
    let profile = applicationSupport.appending(path: "Google/Chrome/Default")
    try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
    try Data().write(to: profile.appending(path: "Cookies"))
  }

  @Test func aMacWithChromeIsOfferedItsSignInsUntilTheReaderAnswers() async throws {
    try await Self.withMac { applicationSupport, support in
      try Self.installChrome(in: applicationSupport)
      let signIns = LocalSignIns(applicationSupport: applicationSupport, support: support, keys: Keys())

      #expect(await signIns.choice() == .offer(.chrome))

      await signIns.decline()
      #expect(await signIns.choice() == .declined(.chrome))
    }
  }

  @Test func refusingTheKeychainTurnsSignInsDown() async throws {
    try await Self.withMac { applicationSupport, support in
      try Self.installChrome(in: applicationSupport)
      let signIns = LocalSignIns(applicationSupport: applicationSupport, support: support, keys: Keys(refused: true))

      await #expect(throws: SignInFailure.keyRefused) { try await signIns.use(.chrome) }

      #expect(await signIns.choice() == .declined(.chrome))
    }
  }

  @Test func aMacWithoutChromiumBrowsersOffersNothing() async throws {
    try await Self.withMac { applicationSupport, support in
      let signIns = LocalSignIns(applicationSupport: applicationSupport, support: support, keys: Keys())

      #expect(await signIns.choice() == .unavailable)
    }
  }

  @Test func aBrowserInUseThatWasRemovedIsNoLongerUsed() async throws {
    try await Self.withMac { applicationSupport, support in
      try Support(root: support).save(.using(.arc))
      try Self.installChrome(in: applicationSupport)
      let signIns = LocalSignIns(applicationSupport: applicationSupport, support: support, keys: Keys())

      #expect(await signIns.choice() == .declined(.chrome))
    }
  }
}
