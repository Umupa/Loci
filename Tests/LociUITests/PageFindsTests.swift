import Foundation
import LociModel
import Testing

@testable import LociUI

/// H-S7: the one button over a web page, and what clicking it does.
@Suite struct PageFindsTests {
  let article: Item
  let paper: Item

  init() throws {
    var entropy = Sample.Seeded()
    func id(_ offset: Double) -> EntityID {
      EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + offset), entropy: &entropy)
    }
    article = try Item(
      id: id(1), kind: .article, title: "Raft", source: URL(string: "https://raft.github.io/"))
    paper = try Item(
      id: id(2), kind: .paper, title: "In Search of an Understandable Consensus Algorithm",
      source: URL(string: "https://raft.github.io/raft.pdf"))
  }

  static let talks = (1...3).map {
    FoundVideo(
      url: URL(string: "https://www.youtube.com/watch?v=t\($0)")!, title: "Talk \($0)", thumbnail: nil, duration: nil)
  }
  static let papers = [
    FoundPaper(
      url: URL(string: "https://raft.github.io/raft.pdf")!, title: "In Search of an Understandable Consensus Algorithm"),
    FoundPaper(url: URL(string: "https://web.stanford.edu/~ouster/cgi-bin/papers/OngaroPhD.pdf")!, title: "Consensus"),
  ]

  @Test func anArticleWithNothingElseIsKeptInOneClickAndShowsNoNumber() throws {
    let finds = try #require(finds("https://blog.example.com/post", PageFacts(hasArticle: true), library: []))
    #expect(finds.click == .keepPage)
    #expect(finds.count == nil)
    #expect(!finds.kept)
  }

  @Test func aPageLinkingVideosAndPapersOpensTheListAndCountsWhatIsNotKeptYet() throws {
    let finds = try #require(
      finds(
        "https://raft.github.io/", PageFacts(videos: Self.talks, papers: Self.papers, hasArticle: true),
        library: [paper]))
    #expect(finds.click == .choose)
    #expect(finds.count == 5)
    #expect(finds.all.map(\.kind) == [.page, .video, .video, .video, .paper, .paper])
    #expect(finds.all.first { $0.url.lastPathComponent == "raft.pdf" }?.inLibrary == paper.id)
  }

  @Test func onceThePageIsKeptItShowsKeptAndCountsWhatIsLeft() throws {
    let finds = try #require(
      finds("https://raft.github.io/", PageFacts(videos: Self.talks, hasArticle: true), library: [article]))
    #expect(finds.kept)
    #expect(finds.count == 3)
    #expect(finds.click == .choose)
  }

  @Test func whenEverythingIsKeptAClickOpensThePageInTheLibrary() throws {
    let finds = try #require(finds("https://raft.github.io/#intro", PageFacts(hasArticle: true), library: [article]))
    #expect(finds.kept)
    #expect(finds.count == nil)
    #expect(finds.click == .open(article.id))
  }

  @Test func aChannelWithNoArticleListsOnlyItsVideos() throws {
    let finds = try #require(finds("https://www.youtube.com/@cncf/videos", PageFacts(videos: Self.talks), library: []))
    #expect(finds.all.map(\.kind) == [.video, .video, .video])
    #expect(finds.click == .choose)
    #expect(finds.count == 3)
    #expect(!finds.kept)
  }

  @Test func aVideoPageIsItselfTheThingToKeep() throws {
    let finds = try #require(finds("https://www.youtube.com/watch?v=abc", PageFacts(), library: []))
    #expect(finds.all.map(\.kind) == [.page])
    #expect(finds.click == .keepPage)
  }

  @Test func aLinkToThePageItselfIsNotListedTwice() throws {
    let facts = PageFacts(
      papers: [FoundPaper(url: URL(string: "https://example.com/a.pdf#page=2")!, title: "A")], isPDF: true)
    let finds = try #require(finds("https://example.com/a.pdf", facts, library: []))
    #expect(finds.all.count == 1)
  }

  @Test func episodesPapersAndPDFsAreThemselvesThePageToKeep() throws {
    for address in ["https://www.xiaoyuzhoufm.com/episode/123", "https://arxiv.org/abs/1706.03762"] {
      #expect(finds(address, PageFacts(), library: [])?.click == .keepPage)
    }
    #expect(finds("https://example.com/download", PageFacts(isPDF: true), library: [])?.click == .keepPage)
  }

  /// A long channel: one switch checks every row left, or clears them all once all are checked.
  @Test func theSwitchChecksEveryRowLeftOrClearsThemAll() throws {
    let finds = try #require(finds("https://www.youtube.com/@cncf/videos", PageFacts(videos: Self.talks), library: []))
    let all = Set(finds.left.map(\.url))
    #expect(KeepList.toggled([], of: finds) == all)
    #expect(KeepList.toggled([Self.talks[0].url], of: finds).isEmpty)
    #expect(KeepList.toggled(all, of: finds).isEmpty)
  }

  @Test func aPageWithNothingToKeepHasNoButton() {
    #expect(finds("https://example.com/", PageFacts(), library: []) == nil)
  }

  private func finds(_ address: String, _ facts: PageFacts, library: [Item]) -> PageFinds? {
    guard let url = URL(string: address) else { return nil }
    return PageFinds(at: url, title: "Page", facts: facts, library: library)
  }
}
