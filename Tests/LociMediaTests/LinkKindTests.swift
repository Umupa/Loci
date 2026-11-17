import Foundation
import Testing

@testable import LociMedia

struct LinkKindTests {
  static let cases: [(String, LinkKind)] = [
    ("https://www.youtube.com/watch?v=abc", .video),
    ("https://youtu.be/abc", .video),
    ("https://m.youtube.com/watch?v=abc", .video),
    ("https://www.bilibili.com/video/BV1xx", .video),
    ("https://b23.tv/abc", .video),
    ("https://vimeo.com/123", .video),
    ("https://example.com/talk.MP4", .video),
    ("https://podcasts.apple.com/cn/podcast/x/id1?i=2", .audio),
    ("https://www.xiaoyuzhoufm.com/episode/abc", .audio),
    ("https://cdn.example.com/ep1.mp3?x=1", .audio),
    ("https://example.com/ep.m4a", .audio),
    ("https://arxiv.org/abs/1706.03762", .paper),
    ("https://arxiv.org/pdf/1706.03762v7", .paper),
    ("https://example.com/paper.pdf", .paper),
    ("https://kubernetes.io/docs/concepts/scheduling-eviction/", .article),
    ("https://www.youtube.com/@channel", .article),
  ]

  @Test(arguments: cases)
  func tellsWhatALinkIsFromItsAddressAlone(link: String, kind: LinkKind) throws {
    #expect(LinkKind(try #require(URL(string: link))) == kind)
  }
}
