import Foundation
import Testing

@testable import LociHost

struct DataFolderTests {
  static let home = URL(filePath: "/Users/someone")

  @Test func theBetaKeepsItsDataApartFromTheOlderApp() {
    #expect(DataFolder.choose(environment: [:], home: Self.home) == .use(root: Self.home.appending(path: "Loci-Beta")))
  }

  @Test func betaAndDevKeepSourcesInSeparateSystemCacheFolders() {
    let caches = Self.home.appending(path: "Library/Caches", directoryHint: .isDirectory)
    let beta = DataFolder.sourceCache(in: caches, appName: "Loci (Beta)")
    let dev = DataFolder.sourceCache(in: caches, appName: nil)
    #expect(beta.path == "/Users/someone/Library/Caches/Loci-Beta/sources")
    #expect(dev.path == "/Users/someone/Library/Caches/Loci-Dev/sources")
  }

  @Test func theEnvironmentCanPointElsewhere() {
    #expect(
      DataFolder.choose(environment: ["LOCI_ROOT": "/tmp/loci-test"], home: Self.home)
        == .use(root: URL(filePath: "/tmp/loci-test")))
    #expect(
      DataFolder.choose(environment: ["LOCI_ROOT": "~/Elsewhere"], home: Self.home)
        == .use(root: Self.home.appending(path: "Elsewhere")))
  }

  @Test(arguments: [
    "/Users/someone/Loci", "/Users/someone/Loci/", "~/Loci", "/Users/someone/./Loci", "/Users/someone/x/../Loci",
  ])
  func theOlderAppsFolderIsRefused(root: String) {
    #expect(
      DataFolder.choose(environment: ["LOCI_ROOT": root], home: Self.home) == .refuse(path: "/Users/someone/Loci"))
  }
}
