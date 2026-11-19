import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociMedia

struct YtDlpTests {
  static let link = URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!
  static let folder = URL(filePath: "/tmp/item/.work")

  static func ytDlp(
    _ runner: ScriptedRunner, browser: BrowserLogin = .none, cookies: URL? = nil, proxy: String? = nil
  ) -> YtDlp {
    YtDlp(
      executable: URL(filePath: "/opt/homebrew/bin/yt-dlp"), ffmpeg: URL(filePath: "/support/ffmpeg/ffmpeg"),
      quickJS: URL(filePath: "/support/quickJS/qjs"), signIn: .init(browser: browser, cookies: cookies), proxy: proxy,
      runner: runner)
  }

  @Test func resolvingReadsTheJSONAndKeepsItForLater() async throws {
    let json = try Fixture.data("youtube")
    let runner = ScriptedRunner(output: String(decoding: json, as: UTF8.self))

    let (info, kept) = try await Self.ytDlp(runner).resolve(Self.link)

    #expect(info.title == "Me at the zoo")
    #expect(kept == json)
    let arguments = try #require(runner.calls.first?.arguments)
    #expect(arguments.suffix(3) == ["-J", "--no-playlist", Self.link.absoluteString])
    #expect(arguments.contains("--ffmpeg-location"))
    #expect(arguments.contains("quickjs:/support/quickJS/qjs"))
  }

  @Test func recognizingAsksOnlyTheSitesYtDlpKnowsByName() async throws {
    let json = try Fixture.data("youtube")
    let runner = ScriptedRunner(output: String(decoding: json, as: UTF8.self))

    let recognized = try await Self.ytDlp(runner).recognize(Self.link)

    #expect(recognized?.info.title == "Me at the zoo")
    let arguments = try #require(runner.calls.first?.arguments)
    #expect(
      arguments.suffix(5) == ["-J", "--no-playlist", "--use-extractors", "default,-generic", Self.link.absoluteString])
  }

  @Test func aLinkNoSiteKnowsIsNotRecognized() async throws {
    let runner = ScriptedRunner { _ in
      (
        [],
        ProgramResult(status: 1, output: "", diagnostics: "ERROR: No suitable extractor found for URL https://x.dev/a")
      )
    }

    #expect(try await Self.ytDlp(runner).recognize(URL(string: "https://x.dev/a")!) == nil)
  }

  @Test func aVideoDownloadsAsCompatible1080pMergedIntoMP4() {
    let arguments = YtDlp.downloadArguments(.link(Self.link), audio: false, folder: Self.folder)

    #expect(arguments.contains("vcodec:h264,res:1080,acodec:m4a"))
    #expect(arguments.contains("--merge-output-format"))
    #expect(arguments.contains("media.%(ext)s"))
    #expect(arguments.contains("--continue"))
    #expect(!arguments.contains("-x"))
  }

  @Test func anEpisodeDownloadsOnlyItsSoundAsM4A() {
    let arguments = YtDlp.downloadArguments(.link(Self.link), audio: true, folder: Self.folder)

    #expect(arguments.starts(with: ["-f", "ba[ext=m4a]/ba/b", "-x", "--audio-format", "m4a"]))
    #expect(!arguments.contains("--merge-output-format"))
  }

  @Test func aDownloadUsesWhatResolvingReadInsteadOfReadingThePageAgain() async throws {
    let runner = ScriptedRunner { _ in ([], ProgramResult(status: 0, output: "/w/media.mp4\n")) }
    let info = Self.folder.appending(path: "info.json")

    _ = try await Self.ytDlp(runner).download(Self.link, info: info, audio: false, into: Self.folder) { _ in }

    let arguments = try #require(runner.calls.first?.arguments)
    #expect(arguments.suffix(2) == ["--load-info-json", info.path(percentEncoded: false)])
    #expect(!arguments.contains(Self.link.absoluteString))
  }

  @Test func whenWhatResolvingReadHasExpiredTheLinkIsReadAfresh() async throws {
    let runner = ScriptedRunner { call in
      call.arguments.contains("--load-info-json")
        ? (
          [], ProgramResult(status: 1, output: "", diagnostics: "ERROR: unable to download video data: HTTP Error 403")
        )
        : ([], ProgramResult(status: 0, output: "/w/media.mp4\n"))
    }

    let file = try await Self.ytDlp(runner).download(
      Self.link, info: Self.folder.appending(path: "info.json"), audio: false, into: Self.folder
    ) { _ in }

    #expect(file == URL(filePath: "/w/media.mp4"))
    #expect(runner.calls.count == 2)
    #expect(runner.calls.last?.arguments.last == Self.link.absoluteString)
    #expect(runner.calls.last?.arguments.contains("--check-formats") == true)
  }

  @Test func whenThePreferredFormatIsRefusedItTriesOneThatCanBeDownloaded() async throws {
    let runner = ScriptedRunner { call in
      call.arguments.contains("--check-formats")
        ? ([], ProgramResult(status: 0, output: "/w/media.mp4\n"))
        : (
          [], ProgramResult(status: 1, output: "", diagnostics: "ERROR: unable to download video data: HTTP Error 403")
        )
    }

    let file = try await Self.ytDlp(runner).download(Self.link, audio: false, into: Self.folder) { _ in }

    #expect(file == URL(filePath: "/w/media.mp4"))
    #expect(runner.calls.map { $0.arguments.contains("--check-formats") } == [false, true])
  }

  @Test func theDownloadSaysWhereTheFileIsAndHowFarItGot() async throws {
    let runner = ScriptedRunner { _ in
      (
        [
          #"[loci] {"filename": "/w/media.f137.mp4", "downloaded_bytes": 50, "total_bytes": 100}"#,
          #"[loci] {"filename": "/w/media.f137.mp4", "downloaded_bytes": 100, "total_bytes": 100}"#,
          #"[loci] {"filename": "/w/media.f140.m4a", "downloaded_bytes": 5, "total_bytes": 10}"#,
          "not progress",
        ],
        ProgramResult(status: 0, output: "/w/media.mp4\n")
      )
    }
    let heard = Mutex<[Fraction?]>([])

    let file = try await Self.ytDlp(runner).download(Self.link, audio: false, into: Self.folder) { share in
      heard.withLock { $0.append(share) }
    }

    #expect(file == URL(filePath: "/w/media.mp4"))
    #expect(heard.withLock { $0 }.map { (($0?.value ?? -1) * 100).rounded() } == [45, 90, 95])
  }

  @Test func progressWithoutASizeIsUnknownRatherThanZero() {
    let heard = Mutex<[Fraction?]>([])
    let progress = DownloadProgress(audio: true) { share in heard.withLock { $0.append(share) } }

    progress.hear(#"[loci] {"filename": "a", "downloaded_bytes": 5}"#)
    progress.hear(#"[loci] {"filename": "a", "fragment_index": 3, "fragment_count": 4}"#)

    #expect(heard.withLock { $0 } == [nil, Fraction(0.75)])
  }

  @Test func signInChoicesAndTheProxyGoToEveryRun() async throws {
    let runner = ScriptedRunner(output: String(decoding: try Fixture.data("youtube"), as: UTF8.self))
    let cookies = URL(filePath: "/support/cookies.txt")

    _ = try await Self.ytDlp(runner, browser: .chrome, cookies: cookies, proxy: "http://127.0.0.1:7890").resolve(
      Self.link)

    let arguments = try #require(runner.calls.first?.arguments)
    #expect(arguments.contains("--cookies-from-browser"))
    #expect(arguments.contains("chrome"))
    #expect(arguments.contains("/support/cookies.txt"))
    #expect(arguments.contains("http://127.0.0.1:7890"))
  }

  @Test func whenTheBrowsersCookiesCannotBeReadItFetchesWithoutThem() async throws {
    let json = String(decoding: try Fixture.data("youtube"), as: UTF8.self)
    let runner = ScriptedRunner { call in
      call.arguments.contains("--cookies-from-browser")
        ? ([], ProgramResult(status: 1, output: "", diagnostics: "ERROR: could not find chrome cookies database"))
        : ([], ProgramResult(status: 0, output: json))
    }

    let (info, _) = try await Self.ytDlp(runner, browser: .chrome).resolve(Self.link)

    #expect(info.title == "Me at the zoo")
    #expect(runner.calls.count == 2)
    #expect(runner.calls.last?.arguments.contains("--cookies-from-browser") == false)
  }

  @Test(arguments: [
    ("ERROR: [youtube] x: Sign in to confirm your age. This video may be inappropriate", MediaError.Kind.needsLogin),
    ("ERROR: [youtube] x: Video unavailable. This video has been removed by the uploader", .unavailable),
    ("ERROR: [Douyin] 6961737553342991651: Fresh cookies (not necessarily logged in) are needed", .needsLogin),
    ("ERROR: [apple:podcasts] x: Unable to extract JS asset path; please report this issue on …", .outdated),
    ("ERROR: Unsupported URL: https://example.com/", .unavailable),
    (
      "ERROR: Failed to decrypt with DPAPI; could not read cookies from safari: Operation not permitted",
      .cookiesUnreadable
    ),
    ("WARNING: [youtube] No supported JavaScript runtime could be found. n challenge solving failed", .needsJavaScript),
    ("ERROR: unable to download webpage: <urlopen error timed out>", .network),
    ("ERROR: [youtube] O_zcc6XI12g: This video is unavailable", .unavailable),
    ("ERROR: Postprocessing: Conversion failed!", .other),
  ])
  func failuresAreSortedByWhatTheReaderCanDo(said: String, kind: MediaError.Kind) {
    let error = MediaError.fromYtDlp("WARNING: something\n\(said)\n")

    #expect(error.kind == kind)
    #expect(!error.reason.hasPrefix("ERROR:"))
  }

  @Test func subtitlesAreSavedAsWebVTTNextToTheInfo() async throws {
    let runner = ScriptedRunner()

    let file = try await Self.ytDlp(runner).subtitles(
      info: Self.folder.appending(path: "info.json"), language: "en", into: Self.folder)

    #expect(file == Self.folder.appending(path: "subs.en.vtt"))
    let arguments = try #require(runner.calls.first?.arguments)
    #expect(arguments.contains("--skip-download"))
    #expect(arguments.contains("--write-subs"))
    #expect(arguments.contains("vtt"))
  }
}
