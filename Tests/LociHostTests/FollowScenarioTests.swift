import Foundation
import LociMedia
import LociModel
import LociStore
import Testing

@testable import LociHost

/// FO-S1–FO-S7 through the host: following a link, the row and the follow page, new episodes, what is in the
/// library, and stopping.
struct FollowScenarioTests {
  static func reader(_ shows: ScriptedFollows.Show...) -> ScriptedFollows {
    let reader = ScriptedFollows()
    for show in shows { reader.set(show) }
    return reader
  }

  /// FO-S1: the card for a link says who it is; once followed it names that follow, and following again
  /// gives the same one.
  @Test func aFollowedLinkIsKnownAndIsNotFollowedTwice() async throws {
    try await withHost(follows: Self.reader(FollowSamples.dwarkesh)) { host, _, _ in
      let link = URL(string: "https://www.youtube.com/channel/UCdwarkesh/videos")!
      let preview = try await host.run(PreviewFollow(link))
      #expect(preview.name == "Dwarkesh Patel")
      #expect(preview.episodes.count == 3)
      #expect(preview.following == nil)

      let follow = try await host.run(StartFollowing(link))
      #expect(try await host.run(PreviewFollow(link)).following == follow.id)
      #expect(try await host.run(StartFollowing(link)).id == follow.id)
      #expect(place(host).follows().count == 1)
    }
  }

  @Test func aLinkThatCannotBeFollowedIsRefusedSayingWhy() async throws {
    try await withHost(follows: Self.reader()) { host, _, _ in
      await #expect(throws: HostError.self) {
        _ = try await host.run(StartFollowing(URL(string: "https://example.com/post")!))
      }
    }
  }

  /// FO-S3, FO-S4, FO-S6: what is out when following is not new; an hour later the line reads the follow again,
  /// a new video lights the row and leads the page, and opening the page puts the dot out.
  @Test func aNewVideoAnHourLaterIsNewUntilThePageIsOpened() async throws {
    let reader = Self.reader(FollowSamples.dwarkesh)
    try await withHost(follows: reader) { host, _, world in
      let follow = try await host.run(StartFollowing(FollowSamples.channel))
      #expect(try await host.followSummaries().first?.fresh == [])

      reader.change(follow.source) { $0.latest.insert(FollowSamples.video("d", day: 0), at: 0) }
      world.advance(minutes: 30)
      for task in await host.sourceLine.look() { await task.value }
      #expect(reader.reads(of: follow.source) == 0)

      world.advance(minutes: 31)
      for task in await host.sourceLine.look() { await task.value }
      #expect(reader.reads(of: follow.source) == 1)
      let summary = try #require(try await host.followSummaries().first)
      #expect(summary.fresh.map(\.title) == ["Video d"])
      #expect(summary.latest?.title == "Video d")
      let page = try #require(try await host.followPage(follow.id))
      #expect(page.entries.map(\.episode.title) == ["Video d", "Video c", "Video b", "Video a"])
      #expect(page.entries.map { $0.isNew(since: page.follow.opened) } == [true, false, false, false])

      _ = try await host.run(SawFollow(follow.id))
      #expect(try await host.followSummaries().first?.fresh == [])
    }
  }

  /// FO-S6: reading the same episodes again changes nothing; a failure is the page's reason until a read works.
  @Test func aFailureIsThePagesReasonUntilAReadWorks() async throws {
    let reader = Self.reader(FollowSamples.zhang)
    try await withHost(follows: reader) { host, _, world in
      let follow = try await host.run(StartFollowing(FollowSamples.show))
      reader.change(follow.source) { $0.failure = FollowFailure(.refused, "denied by IP ACL") }
      world.advance(minutes: 61)
      for task in await host.sourceLine.look() { await task.value }
      #expect(try await host.followPage(follow.id)?.problem == .refused)
      #expect(try await host.followPage(follow.id)?.entries.count == 2)

      reader.change(follow.source) { $0.failure = nil }
      world.advance(minutes: 61)
      for task in await host.sourceLine.look() { await task.value }
      #expect(try await host.followPage(follow.id)?.problem == nil)
      #expect(try host.database.openEvents().isEmpty)
      #expect(try await host.listItems().isEmpty)
    }
  }

  /// FO-S6: follows share the line with sources: no more than four at once.
  @Test func followsShareTheLinesLimits() async throws {
    let reader = ScriptedFollows()
    for index in 1...6 {
      var show = FollowSamples.dwarkesh
      show.preview = FollowPreview(
        source: .youtube(channel: "UC\(index)"), name: "Channel \(index)",
        page: URL(string: "https://www.youtube.com/channel/UC\(index)")!, episodes: [])
      reader.set(show)
    }
    try await withHost(follows: reader) { host, _, world in
      for index in 1...6 {
        _ = try await host.run(StartFollowing(URL(string: "https://www.youtube.com/channel/UC\(index)")!))
      }
      world.advance(minutes: 61)
      let started = await host.sourceLine.look()
      #expect(started.count == SourceLine.most)
      for task in started { await task.value }
    }
  }

  /// FO-S4, FO-S5, FO-S8: past episodes are listed when the page opens; the one taken in is known on the page
  /// and in `loci follow list`, and nothing else is taken in.
  @Test func anEpisodeInTheLibraryIsTickedOnThePage() async throws {
    try await withHost(follows: Self.reader(FollowSamples.dwarkesh)) { host, place, _ in
      let follow = try await host.run(StartFollowing(FollowSamples.channel))
      _ = try await host.run(RefreshFollow(follow.id))
      #expect(try await host.followPage(follow.id)?.entries.last?.episode.title == "Video old")
      #expect(try await host.followPage(follow.id)?.entries.contains { $0.isNew(since: follow.opened) } == false)

      let item = try Item(
        id: EntityID(), kind: .video(duration: nil), title: "Video b",
        source: URL(string: "https://youtu.be/b")!)
      try place.store.add(item, content: "")
      let page = await value(host.subscribe(OneFollow(follow.id))) { page in
        page?.entries.contains { $0.item == item.id } == true
      }
      #expect(page??.entries.first { $0.item != nil }?.episode.title == "Video b")
      let listing = try #require(try await host.run(ListFollows()).first)
      #expect(listing.kept.map(\.item) == [item.id])
      #expect(listing.latest?.title == "Video c")
      #expect(try await host.listItems().count == 1)
    }
  }

  /// FO-S7: stopping takes the follow out of the row and keeps what was taken in; undoing brings it back as it was.
  @Test func stoppingCanBeUndone() async throws {
    try await withHost(follows: Self.reader(FollowSamples.zhang)) { host, place, _ in
      let follow = try await host.run(StartFollowing(FollowSamples.show))
      let item = try Item(
        id: EntityID(), kind: .audio(duration: nil), title: "158",
        source: FollowSamples.episode(158, day: -3).link)
      try place.store.add(item, content: "")

      let stopped = try await host.run(StopFollowing(follow.id))
      #expect(try await host.followSummaries().isEmpty)
      #expect(try await host.followPage(follow.id) == nil)
      #expect((try? place.store.item(item.id)) != nil)

      _ = try await host.run(RestoreFollowing(stopped))
      #expect(try await host.followSummaries().map(\.follow) == [follow])
      #expect(try await host.followPage(follow.id)?.entries.count == 2)
    }
  }

  /// FO-S2: an episode names its show, and whether it is followed.
  @Test func anItemsShowCanBeFollowedFromIt() async throws {
    try await withHost(follows: Self.reader(FollowSamples.zhang)) { host, place, _ in
      let item = try Item(
        id: EntityID(), kind: .audio(duration: nil), title: "158", source: FollowSamples.episode(158, day: -3).link)
      try place.store.add(item, content: "")
      _ = await value(host.subscribe(AllItems())) { !$0.isEmpty }

      let before = try #require(try await host.run(FollowOfItem(item.id)))
      #expect(before.following == nil)
      #expect(FollowLink(before.link) == .apple(1_634_356_920))

      let follow = try await host.run(StartFollowing(before.link))
      #expect(try await host.run(FollowOfItem(item.id))?.following == follow.id)
    }
  }

  private func place(_ host: LocalHost) -> Store { host.store }
}
