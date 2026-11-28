import Foundation
import Testing

@testable import LociModel

struct FollowLinkTests {
  static let followable: [(String, FollowLink)] = [
    ("https://www.youtube.com/@DwarkeshPatel", .youtube(URL(string: "https://www.youtube.com/@DwarkeshPatel")!)),
    ("https://youtube.com/@GPUMODE/videos", .youtube(URL(string: "https://www.youtube.com/@GPUMODE")!)),
    (
      "https://m.youtube.com/channel/UCJgIbYl6C5no72a0NUAPcTA/streams",
      .youtube(URL(string: "https://www.youtube.com/channel/UCJgIbYl6C5no72a0NUAPcTA")!)
    ),
    ("https://www.youtube.com/c/stanfordonline", .youtube(URL(string: "https://www.youtube.com/c/stanfordonline")!)),
    (
      "https://www.youtube.com/feeds/videos.xml?channel_id=UCJgIbYl6C5no72a0NUAPcTA",
      .youtube(URL(string: "https://www.youtube.com/channel/UCJgIbYl6C5no72a0NUAPcTA")!)
    ),
    ("https://www.xiaoyuzhoufm.com/podcast/626b46ea9cbbf0451cf5a962", .xiaoyuzhou("626b46ea9cbbf0451cf5a962")),
    ("https://podcasts.apple.com/cn/podcast/%E5%BC%A0/id1634356920", .apple(1_634_356_920)),
    ("https://feed.xyzfm.space/dk4yh3pkpjp3", .feed(URL(string: "https://feed.xyzfm.space/dk4yh3pkpjp3")!)),
    ("https://example.com/podcast.xml", .feed(URL(string: "https://example.com/podcast.xml")!)),
    ("https://anchor.fm/s/abc/podcast/rss", .feed(URL(string: "https://anchor.fm/s/abc/podcast/rss")!)),
  ]

  @Test(arguments: followable)
  func knowsAChannelShowOrFeedFromItsAddress(link: String, follow: FollowLink) throws {
    #expect(FollowLink(try #require(URL(string: link))) == follow)
  }

  @Test(arguments: [
    "https://www.youtube.com/watch?v=abc", "https://youtu.be/abc", "https://www.youtube.com/@x/community-post/1",
    "https://www.xiaoyuzhoufm.com/episode/6b05746801b0ab432eddab62",
    "https://podcasts.apple.com/cn/podcast/x/id1634356920?i=1000803881972", "https://example.com/feedback",
    "https://example.com/blog/post", "file:///tmp/feed.xml",
  ])
  func leavesOneEpisodeAndAnythingElseAlone(link: String) throws {
    #expect(FollowLink(try #require(URL(string: link))) == nil)
  }

  @Test(arguments: [
    ("https://www.youtube.com/watch?v=jhBF3UaPD2E&t=5", "https://youtu.be/jhBF3UaPD2E"),
    ("https://m.youtube.com/shorts/jhBF3UaPD2E", "https://www.youtube.com/watch?v=jhBF3UaPD2E"),
    (
      "https://www.xiaoyuzhoufm.com/episode/6b05746801b0ab432eddab62?s=1",
      "https://xiaoyuzhoufm.com/episode/6b05746801b0ab432eddab62"
    ),
    (
      "https://podcasts.apple.com/us/podcast/a/id1?i=1000803881972",
      "https://podcasts.apple.com/cn/podcast/b/id1?i=1000803881972"
    ),
    ("https://www.example.com/ep/1/", "https://example.com/ep/1"),
  ])
  func knowsTwoLinksToTheSameEpisode(one: String, other: String) throws {
    #expect(EpisodeKey(try #require(URL(string: one))) == EpisodeKey(try #require(URL(string: other))))
  }

  @Test func tellsDifferentEpisodesApart() throws {
    let one = EpisodeKey(try #require(URL(string: "https://www.youtube.com/watch?v=a")))
    let other = EpisodeKey(try #require(URL(string: "https://www.youtube.com/watch?v=b")))
    #expect(one != other)
  }
}

struct FollowLinkSourceTests {
  @Test func aLinkLeadsToTheFollowOfItsChannelOrShow() throws {
    let channel = FollowLink.youtube(try #require(URL(string: "https://www.youtube.com/channel/UC1")))
    #expect(channel.leads(to: .youtube(channel: "UC1")))
    #expect(!channel.leads(to: .youtube(channel: "UC2")))
    #expect(FollowLink.apple(7).leads(to: .xiaoyuzhou(podcast: "p", apple: 7)))
    #expect(FollowLink.xiaoyuzhou("p").leads(to: .xiaoyuzhou(podcast: "p", apple: nil)))
    #expect(!FollowLink.apple(7).leads(to: .feed(try #require(URL(string: "https://e.com/f.xml")))))
  }

  @Test func aShowsLinkIsItsPage() {
    #expect(FollowLink.xiaoyuzhou("p").url.absoluteString == "https://www.xiaoyuzhoufm.com/podcast/p")
    #expect(FollowLink.apple(7).url.absoluteString == "https://podcasts.apple.com/podcast/id7")
    #expect(FollowLink(FollowLink.apple(7).url) == .apple(7))
  }
}
