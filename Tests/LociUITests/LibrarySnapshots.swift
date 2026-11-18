import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// The library, the media pages, the browser and the media settings, in light and dark, at the size of the
/// design's window, one picture for each state the design draws.
@MainActor
@Suite(.serialized)
struct LibrarySnapshots {
  /// The design's window.
  static let window = CGSize(width: 1280, height: 800)

  static func shoot(
    _ name: String, _ library: SampleLibrary, at place: WindowState, appearance: Snapshot.Appearance,
    recognizing: Bool = false, working: Bool = false, avatar: Avatar? = nil, standIns: StandIns? = nil,
    browser: BrowserSession = BrowserSession(), english: Bool = false, size: CGSize = window
  ) async throws {
    let view = MachineWindow(memory: WindowMemory(recall: { place }, remember: { _ in }), browser: browser)
      .lociHost(
        FakeHost(
          try Sample(problems: false), library: library, recognizing: recognizing, working: working, avatar: avatar)
      )
      .environment(\.standIns, standIns)
    let file = try await Snapshot.render(
      view, named: name, size: size, appearance: appearance, locale: Locale(identifier: english ? "en" : "zh-Hans"),
      settle: .milliseconds(1500))
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  static func reading(_ item: EntityID) -> WindowState {
    WindowState(place: .library(nil), pages: [.item(item)])
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func shelfAndList(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "library-b", try SampleLibrary(), at: WindowState(place: .library(nil)), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func shelfAndListInEnglish(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "library-b-en", try SampleLibrary(), at: WindowState(place: .library(nil)), appearance: appearance, english: true)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func emptyLibrary(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "library-empty", try SampleLibrary(empty: true), at: WindowState(place: .library(nil)), appearance: appearance)
  }

  /// L-S6, L-S7, L-S12: the sentence playing, highlights in the transcript and on the bar, two sentences chosen,
  /// scrolled away from playing.
  @Test(arguments: Snapshot.Appearance.allCases)
  func video(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "video", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(chosen: 10...11, scrolledAway: true)))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func videoInEnglish(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "video-en", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment()), english: true)
  }

  /// L-S5: recognized sentences arriving, with how far recognition has got.
  @Test(arguments: Snapshot.Appearance.allCases)
  func videoRecognizing(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "video-asr", library, at: Self.reading(library.video.id), appearance: appearance, recognizing: true,
      standIns: StandIns(moment: MediaMoment()))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func videoSubtitleMenu(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "video-subtitles", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(chosen: 10...11, scrolledAway: true, subtitleMenuOpen: true)))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func videoHighlights(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "video-hl", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panel: .highlights)))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func podcast(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "podcast", library, at: Self.reading(library.podcast.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment()))
  }

  /// L-S8: Loci reading along beside a podcast.
  @Test(arguments: Snapshot.Appearance.allCases)
  func podcastConversation(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "podcast-chat", library, at: Self.reading(library.podcast.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panel: .conversation)))
  }

  /// L-S8: Loci reading along beside an article, as the design's third scene.
  @Test(arguments: Snapshot.Appearance.allCases)
  func article(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot("article", library, at: Self.reading(library.article.id), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func articleHighlights(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "article-hl", library, at: Self.reading(library.article.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panel: .highlights)))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func browserStart(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("browser-start", try SampleLibrary(), at: WindowState(place: .browser), appearance: appearance)
  }

  /// L-S15: a channel page offers its videos, picked in a list.
  @Test(arguments: Snapshot.Appearance.allCases)
  func browserChannel(appearance: Snapshot.Appearance) async throws {
    let browser = BrowserSession()
    browser.open(URL(string: "https://www.youtube.com/@cncf/videos"))
    let videos = [
      ("Scheduling at Scale: Inside the Kubernetes Scheduler", "34:12", "kube"),
      ("Keeping etcd Healthy at 10,000 Nodes", "29:48", "etcd"),
      ("Kueue: Fair Sharing for Batch and AI Workloads", "31:05", "kueue"),
    ]
    browser.learn(
      PageFacts(
        videos: videos.compactMap { title, duration, id in
          URL(string: "https://www.youtube.com/watch?v=\(id)").map {
            FoundVideo(
              url: $0, title: title,
              thumbnail: Bundle.module.url(forResource: id, withExtension: "jpg", subdirectory: "Fixtures/Covers"),
              duration: duration)
          }
        }))
    try await Self.shoot(
      "browser-video", try SampleLibrary(), at: WindowState(place: .browser), appearance: appearance,
      standIns: StandIns(webPage: Self.webPage("video", appearance), videoPickerOpen: true), browser: browser)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func browserArticle(appearance: Snapshot.Appearance) async throws {
    let browser = BrowserSession()
    browser.open(
      URL(string: "https://blog.cloudflare.com/how-we-built-pingora-the-proxy-that-connects-cloudflare-to-the-internet")
    )
    browser.learn(PageFacts(hasArticle: true))
    try await Self.shoot(
      "browser-article", try SampleLibrary(empty: true), at: WindowState(place: .browser), appearance: appearance,
      standIns: StandIns(webPage: Self.webPage("article", appearance)), browser: browser)
  }

  /// L-S15: one video's page downloads it with no count.
  @Test(arguments: Snapshot.Appearance.allCases)
  func browserSingleVideo(appearance: Snapshot.Appearance) async throws {
    let browser = BrowserSession()
    browser.open(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    try await Self.shoot(
      "browser-single", try SampleLibrary(), at: WindowState(place: .browser), appearance: appearance,
      standIns: StandIns(webPage: Self.webPage("video", appearance)), browser: browser)
  }

  /// L-S14.
  @Test(arguments: Snapshot.Appearance.allCases)
  func mediaSettings(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "settings-media", try SampleLibrary(), at: WindowState(place: .settings(.media)), appearance: appearance)
  }

  static func webPage(_ name: String, _ appearance: Snapshot.Appearance) -> NSImage? {
    SampleLibrary.picture("web-\(name)-\(appearance.rawValue)").flatMap(NSImage.init(data:))
  }
}

extension LibrarySnapshots {
  /// L-S9: a video waiting for a speech model asks for it beside the player.
  @Test(arguments: Snapshot.Appearance.allCases)
  func videoWaitingForModel(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    guard let tokenizer = library.items.first(where: { $0.title.hasPrefix("Let's build") }) else { return }
    try await Self.shoot(
      "video-needs-model", library, at: Self.reading(tokenizer.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(playing: false)))
  }
}

extension LibrarySnapshots {
  /// L-S11, L-S13: a video that is gone keeps saying so on the shelf, with the button that helps.
  @Test(arguments: Snapshot.Appearance.allCases)
  func shelfWithAFailure(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary().withUnavailableVideo()
    try await Self.shoot("library-failed", library, at: WindowState(place: .library(nil)), appearance: appearance)
  }

  /// L-S11: the page of a video that is gone says why in the reader's words, with the original page to open.
  @Test(arguments: Snapshot.Appearance.allCases)
  func videoUnavailable(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary().withUnavailableVideo()
    guard let gone = library.items.last else { return }
    try await Self.shoot(
      "video-unavailable", library, at: Self.reading(gone.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(playing: false)))
  }

  /// A small window: the transcript panel folds away and the controls keep inside the page.
  @Test(arguments: Snapshot.Appearance.allCases)
  func videoInASmallWindow(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "video-small", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment()), size: CGSize(width: 840, height: 560))
  }

  /// The smallest window: the controls fold to the ones that matter.
  @Test(arguments: Snapshot.Appearance.allCases)
  func videoInTheSmallestWindow(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "video-smallest", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment()), size: Size.windowMinimum)
  }
}

extension SampleLibrary {
  /// Adds a YouTube video that is gone: it was opened, so it sits first on the shelf, and having never been
  /// fetched it has no cover and its address for a title.
  func withUnavailableVideo() throws -> SampleLibrary {
    var library = self
    var entropy = Sample.Seeded(state: 77)
    let gone = try Item(
      id: EntityID(at: Date(timeIntervalSince1970: 1_763_000_100), entropy: &entropy), kind: .video(duration: nil),
      title: "youtube.com/watch?v=O_zcc6XI12g", source: URL(string: "https://www.youtube.com/watch?v=O_zcc6XI12g"))
    library.items.append(gone)
    library.jobs.append(
      Job(
        item: gone.id, stage: .resolve,
        state: .failed(
          Job.Failure(
            reason: "[youtube] O_zcc6XI12g: This video is unavailable", remedy: .openSource, cause: .unavailable))))
    library.states[gone.id] = ReadingState(
      position: .item(gone.id, .time(try TimeSpan(start: .zero))), finished: false,
      updatedAt: Timestamp(millisecondsSince1970: 1_763_337_700_000))
    return library
  }
}
