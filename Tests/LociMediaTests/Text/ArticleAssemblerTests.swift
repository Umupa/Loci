import Foundation
import LociMedia
import Testing

@testable import LociMedia

struct ArticleAssemblerTests {
  static let page = URL(string: "https://blog.example.com/posts/scheduler")!

  static func assemble(_ extraction: Extraction, network: FakeNetwork = FakeNetwork([:])) async throws
    -> FetchedArticle
  {
    try await ArticleAssembler(network: network).article(from: extraction, at: page)
  }

  @Test func imagesAreStoredWithTheArticleAndTheTextPointsAtThem() async throws {
    let network = FakeNetwork(["https://cdn.example.com/a.png": .image("A")])
    let article = try await Self.assemble(
      Extraction(title: "Scheduler", markdown: "Intro\n\n![The queue](https://cdn.example.com/a.png)\n\nEnd"),
      network: network)

    let image = try #require(article.images.first)
    #expect(article.images.count == 1)
    #expect(image.data == Data("A".utf8))
    #expect(article.markdown == "Intro\n\n![The queue](images/\(image.name))\n\nEnd")
    #expect(image.name.hasSuffix(".png"))
  }

  @Test func relativeImagesAreFetchedFromThePagesSite() async throws {
    let network = FakeNetwork(["https://blog.example.com/img/b.jpg": .image("B", type: "image/jpeg")])
    let article = try await Self.assemble(
      Extraction(title: "S", markdown: "![b](/img/b.jpg) and <img alt=\"x\" src=\"/img/b.jpg\">"), network: network)

    let name = try #require(article.images.first?.name)
    #expect(name.hasSuffix(".jpg"))
    #expect(article.markdown == "![b](images/\(name)) and <img alt=\"x\" src=\"images/\(name)\">")
  }

  @Test func anImageShownTwiceIsFetchedOnce() async throws {
    let network = FakeNetwork(["https://cdn.example.com/a.png": .image()])
    let article = try await Self.assemble(
      Extraction(title: "S", markdown: "![1](https://cdn.example.com/a.png)\n![2](https://cdn.example.com/a.png)"),
      network: network)

    #expect(network.requests.count == 1)
    #expect(article.images.count == 1)
    #expect(!article.markdown.contains("cdn.example.com"))
  }

  @Test func anImageThatCannotBeFetchedKeepsItsAddress() async throws {
    let network = FakeNetwork(["https://cdn.example.com/ok.png": .image()])
    let article = try await Self.assemble(
      Extraction(title: "S", markdown: "![x](https://cdn.example.com/gone.png) ![y](https://cdn.example.com/ok.png)"),
      network: network)

    #expect(article.markdown.hasPrefix("![x](https://cdn.example.com/gone.png) ![y](images/"))
    #expect(article.images.count == 1)
  }

  @Test func aResponseThatIsNotAnImageIsNotKept() async throws {
    let network = FakeNetwork(["https://cdn.example.com/a.png": .page("<html>blocked</html>")])
    let article = try await Self.assemble(
      Extraction(title: "S", markdown: "![x](https://cdn.example.com/a.png)"), network: network)

    #expect(article.images.isEmpty)
    #expect(article.markdown == "![x](https://cdn.example.com/a.png)")
  }

  @Test func whatThePageSaysAboutItselfIsKept() async throws {
    let article = try await Self.assemble(
      Extraction(
        title: "Scheduler", author: "Ada Lovelace, Alan Turing and Grace Hopper", site: "Example Blog",
        published: "2024-03-05T10:00:00+00:00", language: "en_US", markdown: "Text"))

    #expect(article.title == "Scheduler")
    #expect(article.authors == ["Ada Lovelace", "Alan Turing", "Grace Hopper"])
    #expect(article.site == "Example Blog")
    #expect(article.language == "en-US")
    #expect(article.published == Date(timeIntervalSince1970: 1_709_632_800))
  }

  @Test func aDayAloneIsADateAndAnythingOddIsNone() {
    #expect(ArticleAssembler.date("2024-03-05") == Date(timeIntervalSince1970: 1_709_596_800))
    #expect(ArticleAssembler.date("March 5th") == nil)
    #expect(ArticleAssembler.date("") == nil)
  }

  @Test func anUnusableLanguageIsLeftOut() async throws {
    let article = try await Self.assemble(Extraction(title: "S", language: "english (US)", markdown: "Text"))
    #expect(article.language == nil)
  }

  @Test func aPageWithoutATitleIsNamedAfterItsSite() async throws {
    let article = try await Self.assemble(Extraction(title: " ", domain: "example.com", markdown: "Text"))
    #expect(article.title == "example.com")
  }

  @Test func aPageWithNoTextFails() async throws {
    await #expect(throws: FetchError(reason: "The page has no text to read.", cause: .noArticleText)) {
      try await Self.assemble(Extraction(title: "S", markdown: " \n "))
    }
  }

  @Test func chineseBylinesAreSplitToo() {
    #expect(ArticleAssembler.authors("张三、李四，王五") == ["张三", "李四", "王五"])
  }
}
