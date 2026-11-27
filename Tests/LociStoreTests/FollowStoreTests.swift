import Foundation
import LociModel
import Testing

@testable import LociStore

/// FO-S3, FO-S4, FO-S6: follows are a file that outlives the database; their episodes are kept in it, and only
/// one that came out after those already kept is new.
struct FollowStoreTests {
  static let page = URL(string: "https://www.youtube.com/@DwarkeshPatel")!

  static func follow(_ seed: UInt64 = 1) -> Follow {
    Follow(
      id: Fixture.id(seed), source: .youtube(channel: "UC\(seed)"), name: "Dwarkesh Patel", handle: "@DwarkeshPatel",
      page: page, followed: Fixture.instant)
  }

  static func episode(_ video: String, day: Int64, length: Duration? = nil) -> Episode {
    Episode(
      title: "Episode \(video)", link: URL(string: "https://www.youtube.com/watch?v=\(video)")!,
      published: Timestamp(millisecondsSince1970: day * 86_400_000), length: length)
  }

  static func later(_ minutes: Int64) -> Timestamp {
    Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + minutes * 60_000)
  }

  @Test func followsAreKeptInAFileTheDatabaseCanBeLostWithout() throws {
    try withStore { store in
      try store.changeFollows { $0.append(Self.follow()) }
      let reopened = Store(root: store.root, discard: .permanently)

      #expect(reopened.follows() == [Self.follow()])
      #expect(FileManager.default.fileExists(atPath: store.root.appending(path: "follows.json").path()))
    }
  }

  @Test func theFirstEpisodesKeptAreNotNew() throws {
    let database = try StoreDatabase.inMemory()
    let result = try database.keepEpisodes(
      [Self.episode("a", day: 1), Self.episode("b", day: 2)], of: Self.follow(), at: Self.later(1), fresh: true)

    #expect(result.new == 0)
    let kept = try database.episodes(of: Self.follow().id)
    #expect(kept.map(\.episode.key.description) == ["youtube/b", "youtube/a"])
    #expect(
      kept.allSatisfy {
        !FollowPage.Entry(episode: $0.episode, firstSeen: $0.firstSeen, item: nil).isNew(since: Self.follow().opened)
      })
  }

  @Test func anEpisodeOutAfterTheNewestKeptIsNewAndAnOlderOneListedLaterIsNot() throws {
    let database = try StoreDatabase.inMemory()
    try database.keepEpisodes([Self.episode("b", day: 2)], of: Self.follow(), at: Self.later(1), fresh: true)

    let latest = try database.keepEpisodes(
      [Self.episode("c", day: 3), Self.episode("b", day: 2)], of: Self.follow(), at: Self.later(60), fresh: true)
    let past = try database.keepEpisodes(
      [Self.episode("a", day: 1)], of: Self.follow(), at: Self.later(61), fresh: false)

    #expect(latest.new == 1)
    #expect(past.new == 0)
    let seen = Dictionary(
      uniqueKeysWithValues: try database.episodes(of: Self.follow().id).map {
        ($0.episode.key.description, $0.firstSeen)
      })
    #expect(seen["youtube/c"] == Self.later(60))
    #expect(seen["youtube/a"] == Fixture.instant)
  }

  @Test func readingTheSameEpisodesAgainChangesNothing() throws {
    let database = try StoreDatabase.inMemory()
    let found = [Self.episode("a", day: 1)]
    try database.keepEpisodes(found, of: Self.follow(), at: Self.later(1), fresh: true)

    #expect(try database.keepEpisodes(found, of: Self.follow(), at: Self.later(60), fresh: true).changed == false)
  }

  @Test func aLengthFoundLaterFillsTheEpisodeIn() throws {
    let database = try StoreDatabase.inMemory()
    try database.keepEpisodes([Self.episode("a", day: 1)], of: Self.follow(), at: Self.later(1), fresh: true)
    let result = try database.keepEpisodes(
      [Self.episode("a", day: 1, length: .seconds(2700))], of: Self.follow(), at: Self.later(2), fresh: false)

    #expect(result == (true, 0))
    #expect(try database.episodes(of: Self.follow().id).first?.episode.length == .seconds(2700))
  }

  @Test func onlyTheNewestEpisodesAreKept() throws {
    let database = try StoreDatabase.inMemory()
    let many = (1...(StoreDatabase.mostEpisodes + 5)).map { Self.episode("v\($0)", day: Int64($0)) }
    try database.keepEpisodes(many, of: Self.follow(), at: Self.later(1), fresh: false)

    let kept = try database.episodes(of: Self.follow().id)
    #expect(kept.count == StoreDatabase.mostEpisodes)
    #expect(kept.last?.episode.key.description == "youtube/v6")
  }

  @Test func theStateSaysWhetherTheProblemChangedAndIsForgottenWithTheFollow() throws {
    let database = try StoreDatabase.inMemory()
    let id = Self.follow().id

    #expect(try database.changeFollowState(id) { $0.problem = .refused })
    #expect(try database.changeFollowState(id) { $0.tried = Self.later(1) } == false)
    #expect(try database.followState(id) == .init(tried: Self.later(1), problem: .refused))

    try database.keepEpisodes([Self.episode("a", day: 1)], of: Self.follow(), at: Self.later(1), fresh: false)
    try database.forgetFollow(id)
    #expect(try database.episodes(of: id).isEmpty)
    #expect(try database.followState(id) == .init())
  }
}
