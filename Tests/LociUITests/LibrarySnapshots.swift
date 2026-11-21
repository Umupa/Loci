import AppKit
import Foundation
import LociModel
import SwiftUI
import Synchronization
import Testing

@testable import LociUI

/// The library, the media pages, the browser and the media settings, in light and dark, at the size of the
/// design's window, one picture for each state the design draws.
@MainActor
@Suite(.serialized, .onStage)
struct LibrarySnapshots {
  /// The design's window.
  static let window = CGSize(width: 1280, height: 800)

  static func shoot(
    _ name: String, _ library: SampleLibrary, at place: WindowState, appearance: Snapshot.Appearance,
    recognizing: Bool = false, working: Bool = false, avatar: Avatar? = nil, standIns: StandIns? = nil,
    browser: BrowserSession = BrowserSession(), english: Bool = false, size: CGSize = window, panel: Bool = true,
    machine: MachineChoice? = nil, keyPoints: SampleKeyPoints = .picked, panels: PanelColumn = PanelColumn(slots: []),
    defaults: UserDefaults? = nil,
    until ready: (@MainActor (NSWindow) -> Bool)? = nil
  ) async throws {
    let view = MachineWindow(memory: WindowMemory(recall: { place }, remember: { _ in }), browser: browser)
      .lociHost(
        FakeHost(
          try Sample(problems: false), library: library, recognizing: recognizing, working: working, avatar: avatar,
          panels: panels, keyPoints: keyPoints)
      )
      .environment(\.standIns, standIns)
      .defaultAppStorage(defaults ?? Self.defaults(panel: panel))
      .environment(\.machineChoice, machine)
    let file = try await Snapshot.render(
      view, named: name, size: size, appearance: appearance, locale: Locale(identifier: english ? "en" : "zh-Hans"),
      settle: .milliseconds(1500), until: ready, steady: ready != nil)
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  /// Settings of their own, so what one picture leaves behind is not the next one's: the item panel open or
  /// closed as asked, everything else as it starts.
  static func defaults(panel: Bool) -> UserDefaults {
    let name = "loci-snapshot-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.set(panel, forKey: PanelMemory.key)
    return defaults
  }

  static func reading(_ item: EntityID) -> WindowState {
    WindowState(place: .library(nil), pages: [.item(item)])
  }

  /// I-S7, I-S8: the gallery with work going, paused, waiting for the reader and queued, and the task dock.
  @Test(arguments: Snapshot.Appearance.allCases)
  func gallery(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "library-gallery", try SampleLibrary().withGalleryWork(), at: WindowState(place: .library(nil)),
      appearance: appearance, standIns: StandIns(pointedCard: try SampleLibrary().uring))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func galleryInEnglish(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "library-gallery-en", try SampleLibrary().withGalleryWork(), at: WindowState(place: .library(nil)),
      appearance: appearance, standIns: StandIns(), english: true)
  }

  /// I-S8: the dock opened into the list of tasks.
  @Test(arguments: Snapshot.Appearance.allCases)
  func taskDockOpen(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "task-dock-open", try SampleLibrary().withGalleryWork(), at: WindowState(place: .library(nil)),
      appearance: appearance, standIns: StandIns(pointedCard: try SampleLibrary().uring, taskDockOpen: true))
  }

  /// I-S10: Loci saving a batch lights the window's edges and the dock counts the batch.
  @Test(arguments: Snapshot.Appearance.allCases)
  func lociSaving(appearance: Snapshot.Appearance) async throws {
    var library = try SampleLibrary().withGalleryWork()
    library.saving = SavingBatch(items: library.jobs.prefix(5).map(\.item), finished: 2)
    try await Self.shoot(
      "library-loci-saving", library, at: WindowState(place: .library(nil)), appearance: appearance,
      standIns: StandIns())
  }

  /// A-S7, A-S9, A-S10: two cards chosen, one title being renamed, and the notice after a deletion.
  @Test(arguments: Snapshot.Appearance.allCases)
  func choosingRenamingAndUndoing(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    let cards = library.items.filter { $0.id != library.video.id }
    let actions = ItemActions(rename: { _ in }, changeCover: { _ in }, delete: { _ in })
    let card = CardActions(pause: { _ in }, resume: { _ in }, cancel: { _ in }, fix: { _, _ in })
    let view = ZStack(alignment: .bottom) {
      ScrollView {
        LibraryGallery(
          items: cards, jobs: [:], progress: Progress(), chosen: [cards[1].id, cards[2].id], renaming: cards[4].id,
          click: { _ in }, actions: card, menu: { ItemMenu(item: $0, acted: [$0.id], actions: actions) },
          renamed: { _, _ in }
        )
        .padding(28)
      }
      DeletedNotice(count: 2, undo: {}).padding(.bottom, 24)
    }
    .background(Palette.canvas)
    .environment(\.covers, Covers())
    .lociHost(FakeHost(try Sample(problems: false), library: library))
    let file = try await Snapshot.render(
      view, named: "library-editing", size: CGSize(width: 900, height: 640), appearance: appearance,
      settle: .milliseconds(1000))
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  @Test(arguments: [nil, ItemKind.paper], Snapshot.Appearance.allCases)
  func anEmptyLibraryViewKeepsTheSidebarOnTheLeft(kind: ItemKind?, appearance: Snapshot.Appearance) async throws {
    let host = FakeHost(try Sample(problems: false), library: try SampleLibrary(empty: kind == nil))
    let place = WindowState(place: .library(kind))
    let view = MachineWindow(memory: WindowMemory(recall: { place }, remember: { _ in })).lociHost(host)
    let quiet = Quiet(host.activity)
    let name = kind == nil ? "library-empty" : "library-papers-empty"
    let size = CGSize(width: Size.windowMinimum.width, height: Snapshot.windowSize.height)

    let file = try await Snapshot.render(view, named: name, size: size, appearance: appearance) { window in
      guard quiet.settled(), let content = window.contentView else { return false }
      content.layoutSubtreeIfNeeded()
      #expect(Self.editableField(in: content) != nil)
      return true
    }

    let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: file)))
    let inset = Int(Spacing.l * CGFloat(bitmap.pixelsWide) / size.width)
    let middle = bitmap.pixelsHigh / 2
    let sidebar = try #require(bitmap.colorAt(x: inset, y: middle))
    let canvas = try #require(bitmap.colorAt(x: bitmap.pixelsWide - inset, y: middle))
    #expect(sidebar != canvas)
  }

  private static func editableField(in view: NSView) -> NSTextField? {
    if let field = view as? NSTextField, field.isEditable { return field }
    return view.subviews.lazy.compactMap { editableField(in: $0) }.first
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
  func aTranscriptScrolledAwayFromPlaybackOffersToReturn(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "video-back-to-playing", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(scrolledAway: true)))
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
    try await Self.shoot("article", library, at: Self.reading(library.article.id), appearance: appearance) { window in
      guard let reader = Self.reader(in: window) else { return false }
      return !reader.string.isEmpty
    }
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func articleHighlights(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "article-hl", library, at: Self.reading(library.article.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panel: .highlights))
    ) { window in
      guard let reader = Self.reader(in: window) else { return false }
      return reader.subviews.contains { $0 is NoteDot && reader.visibleRect.intersects($0.frame) }
    }
  }

  private static func reader(in window: NSWindow) -> ReaderTextView? {
    func find(in view: NSView) -> ReaderTextView? {
      if let reader = view as? ReaderTextView { return reader }
      return view.subviews.lazy.compactMap { find(in: $0) }.first
    }
    return window.contentView.flatMap { find(in: $0) }
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
    browser.current.learn(
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
    browser.current.learn(PageFacts(hasArticle: true))
    try await Self.shoot(
      "browser-article", try SampleLibrary(empty: true), at: WindowState(place: .browser), appearance: appearance,
      standIns: StandIns(webPage: Self.webPage("article", appearance)), browser: browser)
  }

  /// B-S5: the start page offers the sign-ins of the browser used most lately.
  @Test(arguments: Snapshot.Appearance.allCases)
  func browserSignInOffer(appearance: Snapshot.Appearance) async throws {
    let browser = BrowserSession(signIns: FakeSignIns(answer: .offer(.chrome)))
    await browser.checkSignIns()
    try await Self.shoot(
      "browser-sign-ins", try SampleLibrary(), at: WindowState(place: .browser), appearance: appearance,
      browser: browser)
  }

  /// B-S2: several tabs show above the address, the one in front raised.
  @Test(arguments: Snapshot.Appearance.allCases)
  func browserTabs(appearance: Snapshot.Appearance) async throws {
    let browser = BrowserSession()
    browser.open(URL(string: "https://www.youtube.com/@cncf/videos"))
    browser.open(
      URL(string: "https://blog.cloudflare.com/how-we-built-pingora-the-proxy-that-connects-cloudflare-to-the-internet")
    )
    browser.current.learn(PageFacts(hasArticle: true))
    try await Self.shoot(
      "browser-tabs", try SampleLibrary(empty: true), at: WindowState(place: .browser), appearance: appearance,
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

  /// L-S14, O-S7, O-S8: storage at the top of the media settings.
  @Test(arguments: Snapshot.Appearance.allCases)
  func mediaSettings(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "settings-media", try SampleLibrary().withStorage(), at: WindowState(place: .settings(.media)),
      appearance: appearance)
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

  @Test(arguments: Snapshot.Appearance.allCases)
  func aDownloadFailureIsVisibleBesideTheAvailableTranscript(appearance: Snapshot.Appearance) async throws {
    var library = try SampleLibrary()
    let video = library.video.id
    library.jobs.removeAll { $0.item == video }
    library.jobs.append(Job(item: video, stage: .download, state: .failed(.init(reason: "HTTP 403"))))
    try await Self.shoot(
      "video-download-failed", library, at: Self.reading(video), appearance: appearance,
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

extension LibrarySnapshots {
  /// I-S12: an item's page opens with the panel folded away until the button at the top right opens it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func thePanelStartsClosed(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "video-panel-closed", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment()), panel: false)
  }

  /// I-S11: a video still downloading shows its preparation in place of the player.
  @Test(arguments: Snapshot.Appearance.allCases)
  func preparing(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary().withGalleryWork()
    try await Self.shoot(
      "preparing", library, at: Self.reading(try library.uring), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(playing: false)), panel: false)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func preparingPaused(appearance: Snapshot.Appearance) async throws {
    var library = try SampleLibrary().withGalleryWork()
    let uring = try library.uring
    library.jobs = library.jobs.map { $0.item == uring ? $0.with(.paused(progress: Fraction(0.62))) : $0 }
    try await Self.shoot(
      "preparing-paused", library, at: Self.reading(uring), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(playing: false)), panel: false)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func preparingNeedsASignIn(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary().withGalleryWork()
    try await Self.shoot(
      "preparing-needs", library, at: Self.reading(try library.named("图解 eBPF")), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(playing: false)), panel: false)
  }
}

extension LibrarySnapshots {
  /// O-S4: another Mac's video that it only watches online says so where the player would be.
  @Test(arguments: Snapshot.Appearance.allCases)
  func anotherMacsOnlineVideo(appearance: Snapshot.Appearance) async throws {
    var library = try SampleLibrary()
    library.videoSaved = false
    let machine = MachineChoice(
      roster: Roster(this: FakeMachines.thisMac, paired: []), shown: FakeMachines.studio, link: .connected,
      menuOpen: false, openMenu: {}, addMac: {}, remove: { _ in }, acceptInvite: { _ in })
    try await Self.shoot(
      "video-remote-online", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(playing: false)), machine: machine)
  }
}

extension LibrarySnapshots {
  /// I-S8: scrolled to the end, the last row of the gallery sits clear above the task dock.
  @Test(arguments: Snapshot.Appearance.allCases)
  func galleryScrolledToTheEnd(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "library-gallery-end", try SampleLibrary().withGalleryWork(), at: WindowState(place: .library(nil)),
      appearance: appearance, standIns: StandIns(galleryAtEnd: true))
  }
}

extension LibrarySnapshots {
  /// The gallery, its glass buttons and the task dock cast their soft shadows as shapes, not with `shadow(_:)`:
  /// no layer behind them carries a wide shadow Core Animation must blur off screen. A dozen such shadows made
  /// every picture of the window take seconds and starved the tests running beside it. A button's one-point
  /// shadow costs next to nothing and is allowed.
  @Test func theGalleryAndTheDockCastNoShadowThatNeedsABlurPass() async throws {
    let library = try SampleLibrary().withGalleryWork()
    let jobs = Dictionary(library.jobs.map { ($0.item, $0) }, uniquingKeysWith: { first, _ in first })
    let card = CardActions(pause: { _ in }, resume: { _ in }, cancel: { _ in }, fix: { _, _ in })
    let actions = ItemActions(rename: { _ in }, changeCover: { _ in }, delete: { _ in })
    let view = ZStack(alignment: .bottom) {
      ScrollView {
        LibraryGallery(
          items: library.items, jobs: jobs, progress: Progress(), chosen: [], renaming: nil, click: { _ in },
          actions: card, menu: { ItemMenu(item: $0, acted: [$0.id], actions: actions) }, renamed: { _, _ in }
        )
        .padding(28)
      }
      TaskDock(
        jobs: library.jobs,
        items: Dictionary(library.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
        saving: nil, actions: DockActions(card: card, stopSaving: {})
      )
      .padding(.bottom, 20)
    }
    .background(Palette.canvas)
    .environment(\.covers, Covers())
    .environment(\.standIns, StandIns(pointedCard: try library.uring, taskDockOpen: true))
    let host = FakeHost(try Sample(problems: false), library: library)
    let quiet = Quiet(host.activity)
    let shadowed = Mutex<[String]>([])

    try await Snapshot.render(
      view.lociHost(host), named: "library-gallery-layers", size: Self.window, appearance: .light
    ) { window in
      guard quiet.settled(), let root = window.contentView?.layer else { return false }
      shadowed.withLock { $0 = Self.shadowedLayers(under: root) }
      return true
    }

    #expect(shadowed.withLock { $0 } == [])
  }

  static func shadowedLayers(under layer: CALayer) -> [String] {
    let wide = layer.shadowOpacity > 0 && layer.shadowColor != nil && layer.shadowRadius > 2
    let own = wide ? ["\(type(of: layer)) \(layer.frame) radius \(layer.shadowRadius)"] : []
    return own + (layer.sublayers ?? []).flatMap { shadowedLayers(under: $0) }
  }
}
