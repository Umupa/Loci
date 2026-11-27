import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

struct UpdateEnvironmentTests {
  private static func system(_ variables: [String: String]) -> UpdateEnvironment {
    UpdateEnvironment.system(
      variables: variables, foreground: { AsyncStream { $0.finish() } }, busy: { AsyncStream { $0.finish() } },
      quit: {})
  }

  @Test func aTestCopyCanBePointedAtALocalFeed() {
    let local = "http://127.0.0.1:8765/latest.json"
    #expect(Self.system(["LOCI_UPDATE_FEED": local]).feed == URL(string: local))
  }

  @Test func withoutTheVariableTheCopyReadsThePublishedFeed() {
    #expect(Self.system([:]).feed == ReleaseFeed.loci)
    #expect(Self.system(["LOCI_UPDATE_FEED": ""]).feed == ReleaseFeed.loci)
  }

  @Test func eachCopyKeepsItsUpdatesUnderItsOwnBundleIdentifier() throws {
    let app = FileManager.default.temporaryDirectory.appending(path: "loci-bundle-\(UUID().uuidString)/Test.app")
    try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
    let info = ["CFBundleIdentifier": "fun.loci.bbtest.update", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: app.appending(path: "Contents/Info.plist"))
    let bundle = try #require(Bundle(url: app))
    let environment = UpdateEnvironment.system(
      bundle: bundle, variables: [:], foreground: { AsyncStream { $0.finish() } },
      busy: { AsyncStream { $0.finish() } }, quit: {})
    #expect(environment.identifier == "fun.loci.bbtest.update")
  }
}
