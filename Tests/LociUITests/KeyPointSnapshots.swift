import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// The key points page, playing only them, an article folded to them, how subtitles look, and a podcast in
/// large words; in light and dark.
@MainActor
@Suite(.serialized)
struct KeyPointSnapshots {
  static func reading(_ item: EntityID) -> WindowState {
    LibrarySnapshots.reading(item)
  }

  /// Subtitles over the picture and the podcast's large words, or none.
  static func defaults(subtitles: Bool = true) -> UserDefaults {
    let defaults = LibrarySnapshots.defaults(panel: true)
    defaults.set(subtitles, forKey: "subtitlesShown")
    defaults.set(SubtitleMode.both.rawValue, forKey: SubtitleMode.key)
    return defaults
  }

  /// K-S2: nothing picked yet; the page offers to pick.
  @Test(arguments: Snapshot.Appearance.allCases)
  func notPicked(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "keypoints-none", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panel: .keyPoints)), keyPoints: .none, defaults: Self.defaults())
  }

  /// K-S2: picking, with the rows shimmering where they will be.
  @Test(arguments: Snapshot.Appearance.allCases)
  func picking(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "keypoints-picking", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panel: .keyPoints)), keyPoints: .picking, defaults: Self.defaults())
  }

  /// K-S3–K-S6: the key points of the video with the one playing washed in amber, only the key points playing.
  @Test(arguments: Snapshot.Appearance.allCases)
  func picked(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "keypoints-video", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panel: .keyPoints, onlyKeyPoints: true)), defaults: Self.defaults())
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func pickedInEnglish(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "keypoints-video-en", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panel: .keyPoints)), english: true, defaults: Self.defaults())
  }

  /// K-S1, K-S4, K-S6: an article's key points beside it, and the article folded to them.
  @Test(arguments: Snapshot.Appearance.allCases)
  func articleFolded(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "keypoints-article", library, at: Self.reading(library.article.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panel: .keyPoints, onlyKeyPoints: true)), defaults: Self.defaults())
  }

  /// S-S1–S-S3: how subtitles look, open beside the player.
  @Test(arguments: Snapshot.Appearance.allCases)
  func subtitleStyle(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "subtitle-style", library, at: Self.reading(library.video.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(styling: true)), defaults: Self.defaults())
  }

  /// S-S5: the same with the panel folded away, the words and the cover larger.
  @Test(arguments: Snapshot.Appearance.allCases)
  func podcastWordsWide(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "podcast-words-wide", library, at: Self.reading(library.podcast.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panelFolded: true)), defaults: Self.defaults())
  }

  /// S-S5: a podcast with subtitles on, in large words over the cover's glow, the panel open beside it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func podcastWords(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "podcast-words", library, at: Self.reading(library.podcast.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(panel: .keyPoints)), defaults: Self.defaults())
  }

  /// S-S5: with subtitles off the podcast is its large cover again.
  @Test(arguments: Snapshot.Appearance.allCases)
  func podcastCover(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "podcast-cover", library, at: Self.reading(library.podcast.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment()), defaults: Self.defaults(subtitles: false))
  }
}
