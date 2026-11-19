import Foundation
import LociHost
import LociMedia
import LociModel
import Synchronization

/// What yt-dlp says about one link.
struct FakeSite: Sendable {
  var title: String
  var site: String? = "Channel"
  var duration: Double? = 120
  var audio = false
  /// WebVTT for the site's own subtitles, in English.
  var subtitles: String?
  var chapters: [(Double, String)] = []
  /// What yt-dlp writes to standard error instead of resolving.
  var refusal: String?

  var json: String {
    let format: [String: Any] = [
      "format_id": "18", "url": "https://media.example.com/play.mp4?expire=4102444800", "ext": "mp4",
      "vcodec": audio ? "none" : "avc1.42001E", "acodec": "mp4a.40.2", "protocol": "https", "height": 360,
    ]
    var info: [String: Any] = [
      "title": title, "timestamp": 1_794_825_900, "thumbnail": "https://img.example.com/cover.jpg",
      "chapters": chapters.map { ["start_time": $0.0, "title": $0.1] as [String: Any] },
      "subtitles": subtitles == nil ? [:] : ["en": [["ext": "vtt"]]], "formats": [format],
    ]
    if let site { info["channel"] = site }
    if let duration { info["duration"] = duration }
    let data = (try? JSONSerialization.data(withJSONObject: info)) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }
}

/// Answers for yt-dlp, FFmpeg, QuickJS and ditto, writing the files they would.
final class FakePrograms: ProgramRunner {
  private let state = Mutex<(sites: [String: FakeSite], calls: [ProgramCall], refuseDownloads: String?)>(([:], [], nil))
  /// Downloads wait here until the test lets them finish.
  let downloads = Latch(open: true)

  func site(_ url: String, _ site: FakeSite) {
    state.withLock { $0.sites[url] = site }
  }

  func refuseDownloads(_ said: String?) {
    state.withLock { $0.refuseDownloads = said }
  }

  var calls: [ProgramCall] { state.withLock { $0.calls } }

  func calls(with flag: String) -> [ProgramCall] {
    calls.filter { $0.arguments.contains(flag) }
  }

  func run(_ call: ProgramCall, line: @escaping @Sendable (String) -> Void) async throws(ProgramError) -> ProgramResult
  {
    state.withLock { $0.calls.append(call) }
    let arguments = call.arguments
    func value(after flag: String) -> String? {
      arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }
    switch call.executable.lastPathComponent {
    case "ditto":
      let folder = URL(filePath: arguments[3])
      try? Data("#!/bin/sh\n".utf8).write(to: folder.appending(path: "yt-dlp_macos"))
      try? Data("#!/bin/sh\n".utf8).write(to: folder.appending(path: "ffmpeg"))
      return ProgramResult(status: 0, output: "")
    case "ffmpeg":
      if let output = arguments.last, output.hasSuffix(".wav") {
        try? Data("RIFF".utf8).write(to: URL(filePath: output))
      }
      return ProgramResult(status: 0, output: "ffmpeg version 9.0.1 Copyright\n")
    case "qjs":
      return ProgramResult(status: 0, output: "QuickJS-ng version 0.10.1\n")
    default:
      break
    }
    if arguments.contains("--version") { return ProgramResult(status: 0, output: "2026.10.26\n") }
    let url = arguments.last ?? ""
    let site = state.withLock { $0.sites[url] }
    if arguments.contains("-J") {
      guard let site else { return ProgramResult(status: 1, output: "", diagnostics: "ERROR: Unsupported URL: \(url)") }
      if let refusal = site.refusal { return ProgramResult(status: 1, output: "", diagnostics: refusal) }
      return ProgramResult(status: 0, output: site.json)
    }
    if arguments.contains("--write-subs"), let folder = value(after: "-P"), let language = value(after: "--sub-langs") {
      let info = value(after: "--load-info-json").flatMap { try? Data(contentsOf: URL(filePath: $0)) }
      let title = info.flatMap { try? JSONDecoder().decode(Titled.self, from: $0) }?.title
      let subtitles = state.withLock { $0.sites.values.first { $0.title == title }?.subtitles }
      if let subtitles {
        try? Data(subtitles.utf8).write(to: URL(filePath: folder).appending(path: "subs.\(language).vtt"))
      }
      return ProgramResult(status: 0, output: "")
    }
    if arguments.contains("--print"), let folder = value(after: "-P") {
      if let refusal = state.withLock({ $0.refuseDownloads }) {
        return ProgramResult(status: 1, output: "", diagnostics: refusal)
      }
      line(#"[loci] {"filename": "a", "downloaded_bytes": 10, "total_bytes": 100}"#)
      await downloads.wait()
      if Task.isCancelled { return ProgramResult(status: 143, output: "") }
      let file = URL(filePath: folder).appending(path: arguments.contains("-x") ? "media.m4a" : "media.mp4")
      try? Data("media".utf8).write(to: file)
      return ProgramResult(status: 0, output: file.path(percentEncoded: false) + "\n")
    }
    return ProgramResult(status: 1, output: "", diagnostics: "ERROR: unexpected call \(arguments)")
  }

  private struct Titled: Decodable {
    let title: String
  }
}

/// The network: images answer with a few bytes, downloads become small files.
final class FakeNetwork: Network {
  private let asked = Mutex<[URL]>([])
  let downloads = Latch(open: true)
  let images = Latch(open: true)
  let folder: URL

  init(folder: URL) {
    self.folder = folder
  }

  var requests: [URL] { asked.withLock { $0 } }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    let url = request.url ?? URL(filePath: "/")
    asked.withLock { $0.append(url) }
    await images.wait()
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])
    return (Data("jpeg".utf8), response ?? HTTPURLResponse())
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    let url = request.url ?? URL(filePath: "/")
    asked.withLock { $0.append(url) }
    progress(Fraction(0.5))
    await downloads.wait()
    let file = folder.appending(path: UUID().uuidString)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? Data("downloaded".utf8).write(to: file)
    return file
  }
}

/// Recognition that hears what the test scripts, and can be held part way.
final class FakeTranscriber: Transcribing {
  private let script: [Heard]
  /// Stops after this many pieces and waits until stopped.
  private let pauseAfter: Int?
  private let starts = Mutex<[Duration]>([])
  private let running = Mutex<(now: Int, most: Int)>((0, 0))
  let gate = Latch(open: true)

  init(_ script: [Heard], pauseAfter: Int? = nil) {
    self.script = script
    self.pauseAfter = pauseAfter
  }

  var startedFrom: [Duration] { starts.withLock { $0 } }
  var mostAtOnce: Int { running.withLock { $0.most } }

  func transcribe(_ media: URL, model: URL, from start: Duration) -> AsyncThrowingStream<Heard, any Error> {
    starts.withLock { $0.append(start) }
    let (stream, continuation) = AsyncThrowingStream.makeStream(of: Heard.self, throwing: (any Error).self)
    let script = script.filter { heard in
      if case .words(let words) = heard { return (words.first?.start ?? .zero) >= start }
      return true
    }
    let pauseAfter = pauseAfter
    let task = Task { [self] in
      running.withLock { state in
        state.now += 1
        state.most = max(state.most, state.now)
      }
      defer { running.withLock { $0.now -= 1 } }
      await gate.wait()
      for (index, heard) in script.enumerated() {
        if index == pauseAfter {
          while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(20)) }
        }
        if Task.isCancelled { break }
        continuation.yield(heard)
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }

  /// Words a quarter second apart from `start`, as Whisper gives them.
  static func words(_ text: String, from start: Double) -> Heard {
    var time = start
    return .words(
      text.split(separator: " ").map { word in
        defer { time += 0.25 }
        return SpokenWord(
          text: " " + word, start: .milliseconds(Int(time * 1000)), end: .milliseconds(Int((time + 0.2) * 1000)))
      })
  }
}

/// Translates by numbering lines and outlines with one highlight, recording what it was asked.
final class FakeTranscriptAgent: TranscriptAgent {
  private let asked = Mutex<[String]>([])

  var requests: [String] { asked.withLock { $0 } }

  func translate(_ transcript: Transcript, into language: String) async throws(HostError) -> Translation {
    asked.withLock { $0.append("translate \(language)") }
    return try Self.attempt {
      try Translation(language: language, lines: transcript.segments.map { "[\(language)] \($0.text)" })
    }
  }

  func outline(_ transcript: Transcript, title: String) async throws(HostError) -> Outline {
    asked.withLock { $0.append("outline \(title)") }
    return try Self.attempt {
      try Outline(
        chapters: [try .init(start: .zero, title: "Agent chapter")],
        highlights: [
          try .init(
            span: try TimeSpan(start: .zero, end: transcript.segments.first?.end ?? .seconds(1)), title: "Start",
            reason: "It sets up the rest")
        ])
    }
  }

  func translate(passages: [String], into language: String) async throws(HostError) -> [String] {
    asked.withLock { $0.append("passages \(language) \(passages.count)") }
    if let failure = failing.withLock({ $0 }) { throw .invalidRequest(failure) }
    return passages.map { "[\(language)] \($0)" }
  }

  /// Makes passage translations fail with `reason`, or succeed again with `nil`.
  func fail(_ reason: String?) {
    failing.withLock { $0 = reason }
  }

  private let failing = Mutex<String?>(nil)

  private static func attempt<Value>(_ body: () throws -> Value) throws(HostError) -> Value {
    do {
      return try body()
    } catch {
      throw .invalidRequest(String(describing: error))
    }
  }
}

/// Fetches articles and papers from a fixed answer.
struct FakeTextFetcher: TextFetching {
  func article(at url: URL, html: String?) async throws(FetchError) -> FetchedArticle {
    if html == nil, url.path().contains("members") { throw FetchError(reason: "sign in to read", needsLogin: true) }
    return FetchedArticle(
      title: "Borg, Omega, and Kubernetes", authors: ["Brendan Burns"], site: "ACM Queue", published: nil,
      language: "en", markdown: html ?? "# Borg, Omega, and Kubernetes\n\n![](images/figure-1.png)\n",
      images: [FetchedFile(name: "figure-1.png", data: Data("png".utf8))])
  }

  func paper(at url: URL) async throws(FetchError) -> FetchedPaper {
    FetchedPaper(
      title: "Large-scale cluster management at Google with Borg", authors: ["Abhishek Verma"], published: nil,
      pdf: Data("%PDF-1.7".utf8))
  }
}

/// Holds whoever waits until it is opened, or until the waiting task is cancelled.
actor Latch {
  private var isOpen: Bool
  private var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]

  init(open: Bool) {
    isOpen = open
  }

  func close() { isOpen = false }

  func open() {
    isOpen = true
    for each in waiting.values { each.resume() }
    waiting = [:]
  }

  func wait() async {
    guard !isOpen else { return }
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled { continuation.resume() } else { waiting[id] = continuation }
      }
    } onCancel: {
      Task { await self.release(id) }
    }
  }

  private func release(_ id: UUID) {
    waiting.removeValue(forKey: id)?.resume()
  }
}
