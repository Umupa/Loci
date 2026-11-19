import Foundation
import Testing

@testable import LociUI

struct AppVersionTests {
  @Test func readsTheVersionAndBuildABundleWasMadeWith() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "AppVersion-\(UUID().uuidString).app")
    let contents = folder.appending(path: "Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let info: [String: String] = [
      "CFBundleIdentifier": "test.appversion.\(UUID().uuidString)", "CFBundleShortVersionString": "1.1.0",
      "CFBundleVersion": "412",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: contents.appending(path: "Info.plist"))
    let bundle = try #require(Bundle(url: folder))

    #expect(AppVersion(of: bundle).text == "1.1.0 (412)")
  }
}
