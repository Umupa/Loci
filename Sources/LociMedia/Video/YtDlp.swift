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

  /// What is behind a link the address alone does not tell, when one of the sites yt-dlp knows by name has
  /// it; `nil` when none does. yt-dlp's catch-all for any page is left out, so an article stays an article.
  public func recognize(_ url: URL) async throws(MediaError) -> (info: MediaInfo, json: Data)? {
    let result: ProgramResult
    do {
      result = try await run(["-J", "--no-playlist", "--use-extractors", "default,-generic", url.absoluteString])
    } catch  where Self.knowsNoSite(error) {
      return nil
    }
    let json = Data(result.output.utf8)
    return (try MediaInfo(json: json), json)
  }

  private static func knowsNoSite(_ error: MediaError) -> Bool {
    let reason = error.reason.lowercased()
    return reason.hasPrefix("no suitable extractor") || reason.hasPrefix("unsupported url")
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

  /// Downloads into `folder` as `media.mp4` with a picture at most `height` tall, or `media.m4a` for something
  /// to listen to, picking up any part already there. Returns the finished file. With the JSON `resolve` read,
  /// the page is not read again; when the addresses in it no longer work, the link is read afresh, still keeping
  /// the part. The part is thrown away only when the site will not carry it on.
  public func download(
    _ url: URL, info: URL? = nil, audio: Bool, height: Int = 1080, into folder: URL,
    progress: @escaping @Sendable (Fraction?, Job.Amount?) -> Void
  ) async throws(MediaError) -> URL {
    let tracker = DownloadProgress(audio: audio, report: progress)
    let result: ProgramResult
    do {
      result = try await run(
        Self.downloadArguments(info.map(Source.info) ?? .link(url), audio: audio, height: height, folder: folder),
        line: { line in tracker.hear(line) })
    } catch {
      let refused = error.reason.lowercased().contains("unable to download video data: http error 403")
      guard !Task.isCancelled, info != nil || refused else { throw error }
      do {
        let args = Self.downloadArguments(
          .link(url), audio: audio, height: height, folder: folder, checkFormats: refused)
        result = try await run(args, line: { line in tracker.hear(line) })
      } catch  where !Task.isCancelled && Self.partRefused(error) {
        let args = Self.downloadArguments(
          .link(url), audio: audio, height: height, folder: folder, checkFormats: true, afresh: true)
        result = try await run(args, line: { line in tracker.hear(line) })
      }
    }
    let path = result.output.split(whereSeparator: \.isNewline).map(String.init).last { $0.hasPrefix("/") }
    guard let path else { throw MediaError(.other, reason: "yt-dlp finished without saying where the file is") }
    return URL(filePath: path)
  }

  /// Where a download starts from: the link, or the JSON already read from it.
  enum Source {
    case link(URL)
    case info(URL)
  }

  /// The site will not send the rest of the part already downloaded.
  static func partRefused(_ error: MediaError) -> Bool {
    let reason = error.reason.lowercased()
    return reason.contains("http error 416") || reason.contains("requested range not satisfiable")
  }

  static func downloadArguments(
    _ source: Source, audio: Bool, height: Int = 1080, folder: URL, checkFormats: Bool = false, afresh: Bool = false
  ) -> [String] {
    let format =
      audio
      ? ["-f", "ba[ext=m4a]/ba/b", "-x", "--audio-format", "m4a"]
      : [
        "-f", "bv*[height<=\(height)]+ba/b[height<=\(height)]/bv*+ba/b", "-S", "vcodec:h264,res:\(height),acodec:m4a",
        "--merge-output-format", "mp4",
      ]
    let from =
      switch source {
      case .link(let url): [url.absoluteString]
      case .info(let file): ["--load-info-json", file.path(percentEncoded: false)]
      }
    let resume = (checkFormats ? ["--check-formats"] : []) + [afresh ? "--no-continue" : "--continue"]
    return format + resume + [
      "--no-playlist", "-P", folder.path(percentEncoded: false), "-o", "media.%(ext)s",
      "--print", "after_move:filepath", "--no-simulate", "--progress", "--newline",
      "--progress-template", "download:[loci] %(progress)j",
    ] + from
  }

  /// Everything every run shares.
  func commonArguments(useBrowser: Bool) -> [String] {
    var arguments = [
      "--no-colors", "--ignore-config", "--replace-in-metadata", "pre_process:url", MediaInfo.duplicateOP3Scheme, "",
    ]
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
