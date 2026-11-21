import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// I-S1, I-S2, I-S5, I-S6: the import panel over the library, in light and dark.
@MainActor
@Suite(.serialized, .onStage)
struct ImportSnapshots {
  static func shoot(
    _ name: String, _ pending: PendingImport, appearance: Snapshot.Appearance, english: Bool = false,
    lastChoice: ImportChoice? = nil
  ) async throws {
    let library = try SampleLibrary()
    let place = WindowState(place: .library(nil))
    let view = ZStack {
      MachineWindow(memory: WindowMemory(recall: { place }, remember: { _ in }))
      ImportSheet(pending: pending, close: {}, opened: { _ in })
    }
    .environment(\.covers, Covers())
    .environment(\.standIns, StandIns())
    .lociHost(FakeHost(try Sample(problems: false), library: library, lastChoice: lastChoice))
    let file = try await Snapshot.render(
      view, named: name, size: LibrarySnapshots.window, appearance: appearance,
      locale: Locale(identifier: english ? "en" : "zh-Hans"), settle: .milliseconds(1800))
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func aVideoLinkFilledIn(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("import-video", .link(ImportSamples.video), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func aVideoLinkInEnglish(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("import-video-en", .link(ImportSamples.video), appearance: appearance, english: true)
  }

  /// I-S2: translating on a runtime of its own shows the model and effort under it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func translatingOnAChosenRuntime(appearance: Snapshot.Appearance) async throws {
    var choice = ImportChoice.first(readerLanguage: "zh-Hans", speechModel: .largeV3Turbo)
    choice.translation?.runtime = Runtime(provider: .codex, model: "gpt-6.1-sol", effort: .low)
    try await Self.shoot("import-runtime", .link(ImportSamples.video), appearance: appearance, lastChoice: choice)
  }

  /// Several videos chosen in the built-in browser wait in one panel.
  @Test(arguments: Snapshot.Appearance.allCases)
  func videosFromTheBrowser(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("import-videos", .links([ImportSamples.video, ImportSamples.slow]), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func aLinkStillBeingRead(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("import-reading", .link(ImportSamples.slow), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func anEpisode(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("import-episode", .link(ImportSamples.episode), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func filesOnThisMac(appearance: Snapshot.Appearance) async throws {
    let files = [URL(filePath: "/tmp/Design Review.m4a"), URL(filePath: "/tmp/Standup.mp4")]
    try await Self.shoot("import-files", .files(files), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func aLinkAlreadyInTheLibrary(appearance: Snapshot.Appearance) async throws {
    let video = try SampleLibrary().video
    try await Self.shoot("import-saved", .link(try #require(video.source)), appearance: appearance)
  }

  /// The panel casts its deep shadow as a shape: no layer in it carries a wide shadow Core Animation must blur
  /// off screen, which made each picture of it take seconds.
  @Test func thePanelCastsNoShadowThatNeedsABlurPass() async throws {
    let host = FakeHost(try Sample(problems: false), library: try SampleLibrary())
    let quiet = Quiet(host.activity)
    let view = ImportSheet(pending: .link(ImportSamples.video), close: {}, opened: { _ in })
      .environment(\.covers, Covers())
      .environment(\.standIns, StandIns())
      .lociHost(host)
    var shadowed: [String] = []

    try await Snapshot.render(view, named: "import-layers", size: LibrarySnapshots.window, appearance: .light) {
      window in
      guard quiet.settled(), let root = window.contentView?.layer else { return false }
      shadowed = LibrarySnapshots.shadowedLayers(under: root)
      return true
    }

    #expect(shadowed == [])
  }
}
