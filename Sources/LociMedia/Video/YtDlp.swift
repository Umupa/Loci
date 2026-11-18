import Foundation
import LociModel
import os

/// Runs yt-dlp the way Loci needs it: the components it leans on, the reader's sign-in, the system proxy.
public struct YtDlp: Sendable {
  public let executable: URL
  public let ffmpeg: URL?
  public let quickJS: URL?
  public let signIn: SignIn
  /// `http://host:port` or `socks5://host:port`; `nil` connects directly.
  public let proxy: String?
  let runner: any ProgramRunner

  public init(
    executable: URL, ffmpeg: URL?, quickJS: URL?, signIn: SignIn, proxy: String?, runner: any ProgramRunner
  ) {
    self.executable = executable
    self.ffmpeg = ffmpeg
    self.quickJS = quickJS
    self.signIn = signIn
    self.proxy = proxy
    self.runner = runner
  }

  /// Whose cookies to send.
  public struct SignIn: Hashable, Sendable {
    public let browser: BrowserLogin
    /// Cookies handed over by the built-in browser, in Netscape format.
    public let cookies: URL?

    public init(browser: BrowserLogin, cookies: URL?) {
      self.browser = browser
      self.cookies = cookies
    }
  }

  /// Reads what is behind the link, and the JSON it came from so later steps need not ask again.
  public func resolve(_ url: URL) async throws(MediaError) -> (info: MediaInfo, json: Data) {
    let result = try await run(["-J", "--no-playlist", url.absoluteString])
    let json = Data(result.output.utf8)
    return (try MediaInfo(json: json), json)
  }

  /// Saves the site's subtitles in `language` as WebVTT into `folder` and returns the file.
  public func subtitles(info: URL, language: String, into folder: URL) async throws(MediaError) -> URL {
    _ = try await run([
      "--load-info-json", info.path(percentEncoded: false), "--skip-download", "--write-subs", "--sub-langs",
      language, "--sub-format", "vtt/srt/best", "--convert-subs", "vtt", "-P", folder.path(percentEncoded: false),
      "-o", "subs.%(ext)s",
    ])
    return folder.appending(path: "subs.\(language).vtt")
  }

  /// Downloads into `folder` as `media.mp4`, or `media.m4a` for something to listen to, picking up any part
  /// already there. Returns the finished file.
  public func download(
    _ url: URL, audio: Bool, into folder: URL, progress: @escaping @Sendable (Fraction?) -> Void
  ) async throws(MediaError) -> URL {
    let tracker = DownloadProgress(audio: audio, report: progress)
    let result = try await run(
      Self.downloadArguments(url, audio: audio, folder: folder),
      line: { line in tracker.hear(line) })
    let path = result.output.split(whereSeparator: \.isNewline).map(String.init).last { $0.hasPrefix("/") }
    guard let path else { throw MediaError(.other, reason: "yt-dlp finished without saying where the file is") }
    return URL(filePath: path)
  }

  static func downloadArguments(_ url: URL, audio: Bool, folder: URL) -> [String] {
    let format =
      audio
      ? ["-f", "ba[ext=m4a]/ba/b", "-x", "--audio-format", "m4a"]
      : [
        "-f", "bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b", "-S", "vcodec:h264,res:1080,acodec:m4a",
        "--merge-output-format", "mp4",
      ]
    return format + [
      "--no-playlist", "--continue", "-P", folder.path(percentEncoded: false), "-o", "media.%(ext)s",
      "--print", "after_move:filepath", "--no-simulate", "--progress", "--newline",
      "--progress-template", "download:[loci] %(progress)j", url.absoluteString,
    ]
  }

  /// Everything every run shares.
  func commonArguments(useBrowser: Bool) -> [String] {
    var arguments = ["--no-colors", "--ignore-config"]
    if let ffmpeg { arguments += ["--ffmpeg-location", ffmpeg.path(percentEncoded: false)] }
    if let quickJS { arguments += ["--js-runtimes", "quickjs:\(quickJS.path(percentEncoded: false))"] }
    if useBrowser, signIn.browser != .none { arguments += ["--cookies-from-browser", signIn.browser.rawValue] }
    if let cookies = signIn.cookies { arguments += ["--cookies", cookies.path(percentEncoded: false)] }
    if let proxy { arguments += ["--proxy", proxy] }
    return arguments
  }

  /// When the browser's cookies cannot be read, tries once more without them, as if no browser were chosen.
  private func run(_ arguments: [String], line: @escaping @Sendable (String) -> Void = { _ in })
    async throws(MediaError) -> ProgramResult
  {
    do {
      return try await attempt(arguments, useBrowser: true, line: line)
    } catch  where error.kind == .cookiesUnreadable && signIn.browser != .none {
      Logger(subsystem: "Loci", category: "media").notice(
        "could not read \(signIn.browser.rawValue, privacy: .public) cookies; fetching without them")
      return try await attempt(arguments, useBrowser: false, line: line)
    }
  }

  private func attempt(_ arguments: [String], useBrowser: Bool, line: @escaping @Sendable (String) -> Void)
    async throws(MediaError) -> ProgramResult
  {
    let call = ProgramCall(executable: executable, arguments: commonArguments(useBrowser: useBrowser) + arguments)
    let result: ProgramResult
    do {
      result = try await runner.run(call, line: line)
    } catch {
      throw MediaError(.other, reason: error.reason)
    }
    guard result.succeeded else {
      if Task.isCancelled { throw MediaError(.other, reason: "stopped") }
      throw MediaError.fromYtDlp(result.diagnostics)
    }
    return result
  }
}
