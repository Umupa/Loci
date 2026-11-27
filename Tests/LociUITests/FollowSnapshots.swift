import Foundation
import LociModel
import Testing

@testable import LociUI

/// FO-S1, FO-S3, FO-S4, FO-S6: the row of follows over the videos and the podcasts, a channel's and a show's
/// follow page, and the follow card under the link field.
@MainActor
@Suite(.serialized, .onStage)
struct FollowSnapshots {
  static func library() throws -> SampleLibrary {
    var library = try SampleLibrary()
    library.follows = SampleFollows.pages(keeping: library.video.id)
    return library
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func videosWithTheirFollows(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "follow-row-videos", try Self.library(), at: WindowState(place: .library(.video)), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func podcastsWithTheirFollows(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "follow-row-podcasts", try Self.library(), at: WindowState(place: .library(.audio)), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func aChannelsFollowPage(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "follow-page-video", try Self.library(),
      at: WindowState(place: .library(.video), pages: [.follow(SampleFollows.id(1))]), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func aShowsFollowPageThatCouldNotBeRead(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "follow-page-podcast", try Self.library(),
      at: WindowState(place: .library(.audio), pages: [.follow(SampleFollows.id(4))]), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func theFollowCardForAPastedChannel(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "follow-card", try Self.library(), at: WindowState(place: .library(.video)), appearance: appearance,
      standIns: StandIns(followCard: SampleFollows.preview.page))
  }
}
