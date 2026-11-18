import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// The library against the real yt-dlp, FFmpeg, network and whisper.cpp. Skipped unless
/// `LOCI_MEDIA_LIVE=1`. Components come from this Mac (Homebrew); the Base model is downloaded once into
/// `~/Library/Caches/loci-media-live` and kept there. How long each step took is appended to
/// `output/media-live.log`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_MEDIA_LIVE"] == "1"))
struct MediaLiveTests {
  static let cache = URL.cachesDirectory.appending(path: "loci-media-live", directoryHint: .isDirectory)

  static func environment(support: URL) -> HostEnvironment {
    let media = MediaEnvironment(
      support: support, runner: SystemRunner(), network: SystemNetwork(), transcriber: WhisperTranscriber(),
      searchPaths: ComponentLocator.systemSearchPaths(environment: ProcessInfo.processInfo.environment),
      proxy: { SystemProxy.current() }, readerLanguage: "zh-Hans")
    return HostEnvironment(
      newID: { EntityID() }, now: { Timestamp(.now) }, defaultRuntime: Runtime(provider: .pi), discard: .permanently,
      agents: { _ in nil }, media: media)
  }

  private func live(_ name: String, _ body: (LocalHost) async throws -> Void) async throws {
    let place = Place()
    defer { place.remove() }
    let host = try await LocalHost.start(
      root: place.root, database: place.database, environment: Self.environment(support: Self.cache))
    _ = try await host.run(SetSpeechModel(.base))
    if try await host.run(ReadMediaSetup()).speechModels.first(where: { $0.model == .base })?.state != .ready {
      let started = ContinuousClock.now
      _ = try await host.run(DownloadSpeechModel(.base))
      let ready = await value(host.subscribe(MediaSettings()), within: .seconds(600)) {
        $0.speechModels.contains { $0 == SpeechModelStatus(model: .base, state: .ready) }
      }
      try #require(ready != nil)
      Timings.note("base model download", since: started)
    }
    do {
      try await body(host)
    } catch {
      await host.close()
      throw error
    }
    await host.close()
  }

  /// Pastes the link, then times how long until it plays and until it has a transcript.
  private func pasteAndRead(_ link: String, _ name: String, host: LocalHost) async throws -> MediaPage {
    let started = ContinuousClock.now
    let item = try await host.run(AddLink(url: URL(string: link)!))
    var playback: Playback?
    while playback == nil, ContinuousClock.now - started < .seconds(60) {
      playback = try? await host.run(ReadPlayback(item: item.id))
      if playback == nil { try await Task.sleep(for: .milliseconds(200)) }
    }
    let playing = try #require(playback, "\(name) never became playable")
    Timings.note("\(name): playable (\(Self.describe(playing)))", since: started)
    let finished = await job(host, item.id, within: .seconds(900)) { job in
      switch job?.state {
      case nil, .done?, .waiting(.agent)?, .failed?: true
      default: false
      }
    }
    let state = finished??.state
    if case .failed(let failure) = state { Issue.record("\(name) failed: \(failure.reason)") }
    let page = try await host.run(ReadMediaPage(item: item.id))
    let count = page.transcript?.segments.count ?? 0
    let origin = String(describing: page.transcript?.origin)
    Timings.note("\(name): transcript of \(count) sentences, \(origin)", since: started)
    #expect(count > 0)
    #expect(page.downloaded)
    return page
  }

  private static func describe(_ playback: Playback) -> String {
    switch playback {
    case .downloaded: "file"
    case .online(let stream): stream.audioOnly ? "online, sound first" : "online"
    }
  }

  @Test func aYouTubeVideoWithSubtitlesPlaysAndReads() async throws {
    try await live("youtube") { host in
      let page = try await pasteAndRead(
        "https://www.youtube.com/watch?v=jNQXAC9IVRw", "YouTube (subtitles)", host: host)
      #expect(page.transcript?.origin == .platform)
    }
  }

  @Test func aBilibiliVideoPlaysAndIsRecognized() async throws {
    try await live("bilibili") { host in
      let page = try await pasteAndRead("https://www.bilibili.com/video/BV1GJ411x7h7", "Bilibili (Base)", host: host)
      #expect(page.transcript?.origin == .recognized(.base))
    }
  }

  @Test func anApplePodcastsEpisodePlaysAndIsRecognized() async throws {
    try await live("podcast") { host in
      let page = try await pasteAndRead(
        "https://podcasts.apple.com/us/podcast/finally-a-vaccine-for-cancer/id1200361736?i=1000802251165",
        "Apple Podcasts (Base)", host: host)
      #expect(page.transcript?.origin == .recognized(.base))
    }
  }

  @Test func aXiaoyuzhouEpisodePlays() async throws {
    try await live("xiaoyuzhou") { host in
      let started = ContinuousClock.now
      let episode = URL(string: "https://www.xiaoyuzhoufm.com/episode/65a0dd421519ccb103f3e16a")!
      let item = try await host.run(AddLink(url: episode))
      #expect(await job(host, item.id, within: .seconds(60), where: isRunning(.download)) != nil)
      let playing = try await host.run(ReadPlayback(item: item.id))
      Timings.note("Xiaoyuzhou: playable (\(Self.describe(playing)))", since: started)
      _ = try await host.run(CancelJob(item: item.id))
    }
  }

  @Test func quickJSInstallsIntoLocisOwnFolder() async throws {
    let support = FileManager.default.temporaryDirectory.appending(path: "loci-live-support-\(UUID())")
    defer { try? FileManager.default.removeItem(at: support) }
    let place = Place()
    defer { place.remove() }
    let host = try await LocalHost.start(
      root: place.root, database: place.database, environment: Self.environment(support: support))
    let started = ContinuousClock.now

    _ = try await host.run(InstallComponent(.quickJS))

    let installed = await value(host.subscribe(MediaSettings()), within: .seconds(120)) {
      if case .managed = $0.components[2].installation { return true }
      return false
    }
    Timings.note("QuickJS install: \(String(describing: installed?.components[2].installation))", since: started)
    #expect(installed != nil)
    await host.close()
  }
}

func job(
  _ host: LocalHost, _ item: EntityID, within timeout: Duration, where match: @escaping @Sendable (Job?) -> Bool
) async -> Job?? {
  let found = await first(host.subscribe(ItemJob(item: item)), within: timeout) { delivered in
    if case .value(let job) = delivered { return match(job) }
    return false
  }
  guard case .value(let job) = found else { return nil }
  return .some(job)
}

enum Timings {
  static func note(_ what: String, since start: ContinuousClock.Instant) {
    let elapsed = ContinuousClock.now - start
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let line = String(format: "%@\t%.1f s\n", what, seconds)
    let log = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appending(path: "output/media-live.log")
    try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: log) {
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: Data(line.utf8))
      try? handle.close()
    } else {
      try? Data(line.utf8).write(to: log)
    }
  }
}
