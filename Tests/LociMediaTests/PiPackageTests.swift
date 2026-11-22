import Testing

@testable import LociMedia

struct PiPackageTests {
  @Test(arguments: ["../outside", "/pi/main", "pi/../outside", "other/pi", "pi/./main", "pi//main"])
  func pathsOutsideThePackageOrWithoutACanonicalNameAreRejected(path: String) {
    #expect(!PiPackage.allowedEntries("pi/\npi/pi\n\(path)\n", details: "d pi/\n- pi/pi\n- \(path)\n"))
  }

  @Test func aPackageContainsOnlyDirectoriesAndRegularFilesUnderPi() {
    let paths = "pi/\npi/pi\npi/docs/\npi/docs/README.md\n"
    #expect(PiPackage.allowedEntries(paths, details: "d pi/\n- pi/pi\nd pi/docs/\n- pi/docs/README.md\n"))
    #expect(!PiPackage.allowedEntries(paths, details: "d pi/\n- pi/pi\nd pi/docs/\nl pi/docs/README.md\n"))
    #expect(!PiPackage.allowedEntries(paths, details: "d pi/\n- pi/pi\nd pi/docs/\nh pi/docs/README.md\n"))
  }

  @Test func bothOfficialDownloadsArePinnedAndOnlyIntelNeedsResigning() {
    let arm = PiPackage.official(arm: true)
    let intel = PiPackage.official(arm: false)
    #expect(arm.version == "1.6.0")
    #expect(arm.version == intel.version)
    #expect(arm.sha256.count == 64 && intel.sha256.count == 64 && arm.sha256 != intel.sha256)
    #expect(arm.url.lastPathComponent == "pi-darwin-arm64.tar.gz")
    #expect(intel.url.lastPathComponent == "pi-darwin-x64.tar.gz")
    #expect(arm.architecture == .arm64 && intel.architecture == .x64)
    #expect(!arm.resign && intel.resign)
    #expect(ComponentPackage.of(.bundledPi, arm: true).format == .piTarGzip(arm))
  }
}
