import Foundation
import Testing

@testable import LociHost

struct DataFolderTests {
  static let home = URL(filePath: "/Users/someone")

  @Test func aDevelopmentBuildKeepsItsDataApartFromTheOlderApp() {
    #expect(DataFolder.choose(environment: [:], home: Self.home) == .use(root: Self.home.appending(path: "Loci Dev")))
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
