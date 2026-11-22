import Foundation
import LociModel
import Testing

@testable import LociUI

/// E-S1–E-S8: an episode's page, the play bar and a video in the corner; in light and dark.
@MainActor
@Suite(.serialized, .onStage)
struct EpisodeSnapshots {
  /// E-S2, E-S3, E-S5: the head, the chapters and the transcript in turns of talk, the sentence playing washed,
  /// each paragraph's translation under it, and the play bar below.
  @Test(arguments: Snapshot.Appearance.allCases)
  func episode(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "episode", library, at: LibrarySnapshots.reading(library.podcast.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment()), defaults: Self.defaults(.both))
  }

  /// E-S3: scrolled away from the sentence playing, with only the original showing.
  @Test(arguments: Snapshot.Appearance.allCases)
  func scrolledAway(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "episode-scrolled-away", library, at: LibrarySnapshots.reading(library.podcast.id), appearance: appearance,
      standIns: StandIns(moment: MediaMoment(scrolledAway: true, panelFolded: true)), defaults: Self.defaults(.original)
    )
  }

  /// E-S1: the episode goes on playing in the bar over the main conversation.
  @Test(arguments: Snapshot.Appearance.allCases)
  func playBar(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "play-bar", library, at: WindowState(), appearance: appearance,
      standIns: StandIns(listening: library.podcast.id))
  }

  /// E-S8: a video left while playing goes on in the corner over the main conversation, its subtitles with it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func videoCorner(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await LibrarySnapshots.shoot(
      "video-corner", library, at: WindowState(), appearance: appearance,
      standIns: StandIns(listening: library.video.id), defaults: KeyPointSnapshots.defaults())
  }

  static func defaults(_ mode: SubtitleMode) -> UserDefaults {
    let defaults = LibrarySnapshots.defaults(panel: true)
    defaults.set(mode.rawValue, forKey: SubtitleMode.key)
    return defaults
  }
}
