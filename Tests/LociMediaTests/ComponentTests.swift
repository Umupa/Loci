import Foundation
import LociModel
import Testing

@testable import LociMedia

struct ComponentTests {
  static let managed = URL(filePath: "/support/components")

  static func locator(present: Set<String>, runner: ScriptedRunner) -> ComponentLocator {
    ComponentLocator(
      managed: managed, searchPaths: [URL(filePath: "/opt/homebrew/bin"), URL(filePath: "/usr/bin")],
      isExecutable: { present.contains($0.path(percentEncoded: false)) }, runner: runner)
  }

  static let versions = ScriptedRunner { call in
    switch call.executable.lastPathComponent {
    case "yt-dlp", "yt-dlp_macos": ([], ProgramResult(status: 0, output: "2026.10.26\n"))
    case "ffmpeg": ([], ProgramResult(status: 0, output: "ffmpeg version 9.0.1 Copyright (c) 2000-2026\n"))
    default: ([], ProgramResult(status: 1, output: "", diagnostics: "QuickJS-ng version 0.10.1\nusage: qjs\n"))
    }
  }

  @Test func aComponentFromHomebrewIsUsedWithItsVersion() async {
    let located = await Self.locator(present: ["/opt/homebrew/bin/yt-dlp"], runner: Self.versions).locate(.ytDlp)

    #expect(located.status.installation == .system(path: "/opt/homebrew/bin/yt-dlp", version: "2026.10.26"))
    #expect(located.executable == URL(filePath: "/opt/homebrew/bin/yt-dlp"))
  }

  @Test func onceLociManagesAComponentItsOwnCopyWins() async {
    let locator = Self.locator(
      present: ["/opt/homebrew/bin/ffmpeg", "/support/components/ffmpeg/ffmpeg"], runner: Self.versions)

    let located = await locator.locate(.ffmpeg)

    #expect(located.status.installation == .managed(version: "9.0.1"))
    #expect(located.executable == URL(filePath: "/support/components/ffmpeg/ffmpeg"))
  }

  @Test func aComponentFoundNowhereIsMissing() async {
    let located = await Self.locator(present: [], runner: Self.versions).locate(.quickJS)

    #expect(located.status.installation == .missing)
    #expect(located.executable == nil)
  }

  @Test func quickJSTellsItsVersionInItsHelp() async {
    let located = await Self.locator(present: ["/support/components/quickJS/qjs"], runner: Self.versions).locate(
      .quickJS)

    #expect(located.status.installation == .managed(version: "0.10.1"))
  }

  @Test func homebrewIsSearchedBeforeThePathAndNothingTwice() {
    let paths = ComponentLocator.systemSearchPaths(environment: ["PATH": "/usr/bin:/opt/homebrew/bin:/bin"])

    #expect(
      paths.map { $0.path(percentEncoded: false) } == ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])
  }

  @Test func eachComponentDownloadsFromWhereVimpoGetsIt() {
    #expect(ComponentPackage.of(.ytDlp, arm: true).urls.first?.lastPathComponent == "yt-dlp_macos.zip")
    #expect(ComponentPackage.of(.ytDlp, arm: true).format == .zip)
    #expect(ComponentPackage.of(.ffmpeg, arm: true).urls.first?.path().contains("/macos/arm64/release/") == true)
    #expect(ComponentPackage.of(.quickJS, arm: false).urls.first?.lastPathComponent == "qjs-darwin-x86_64")
    #expect(ComponentPackage.of(.quickJS, arm: true).format == .executable)
  }

  @Test func eachSpeechModelHasItsOwnWhisperFile() {
    let files = SpeechModel.allCases.map(\.fileName)

    #expect(Set(files).count == SpeechModel.allCases.count)
    #expect(SpeechModel.largeV3TurboQuantized.fileName == "ggml-large-v3-turbo-q5_0.bin")
    #expect(SpeechModel.base.source.host() == "huggingface.co")
  }

  @Test func theSystemProxyIsPassedOnInTheFormYtDlpTakes() {
    #expect(
      SystemProxy.from(["HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7890]) == "http://127.0.0.1:7890")
    #expect(
      SystemProxy.from(["SOCKSEnable": 1, "SOCKSProxy": "localhost", "SOCKSPort": 1080]) == "socks5://localhost:1080")
    #expect(SystemProxy.from(["HTTPSEnable": 0, "HTTPSProxy": "127.0.0.1"]) == nil)
  }
}
