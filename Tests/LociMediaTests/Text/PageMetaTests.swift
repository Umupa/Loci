import Foundation
import LociModel
import Testing

@testable import LociMedia

struct PageMetaTests {
  private static let repository = URL(string: "https://github.com/e2b-dev/infra")!

  @Test func aPageWithOpenGraphTagsGivesItsTitlePictureSiteAndDescription() {
    let html = """
      <html><head><title>GitHub - e2b-dev/infra</title>
      <meta property="og:title" content="e2b-dev/infra">
      <meta content="E2B 的沙箱运行时 &amp; 基础设施" property="og:description" />
      <meta property='og:site_name' content='GitHub'>
      <meta property="og:image" content="https://opengraph.githubassets.com/1/e2b-dev/infra">
      </head><body><meta property="og:title" content="not this"></body></html>
      """

    let preview = PageMeta.preview(html: html, at: Self.repository)

    #expect(preview.title == "e2b-dev/infra")
    #expect(preview.site == "GitHub")
    #expect(preview.summary == "E2B 的沙箱运行时 & 基础设施")
    #expect(preview.image == URL(string: "https://opengraph.githubassets.com/1/e2b-dev/infra"))
  }

  @Test func aPageWithoutOpenGraphFallsBackToItsTitleDescriptionAndDomain() {
    let html = """
      <head><TITLE>
        Firecracker &#8212; microVMs
      </TITLE><meta name="description" content="Secure and fast microVMs."></head>
      """

    let preview = PageMeta.preview(html: html, at: URL(string: "https://www.firecracker-microvm.io/")!)

    #expect(preview.title == "Firecracker — microVMs")
    #expect(preview.site == "firecracker-microvm.io")
    #expect(preview.summary == "Secure and fast microVMs.")
    #expect(preview.image == nil)
  }

  @Test func aGitHubRepositoryIsTitledByItsOwnerAndNameAlone() {
    let html = """
      <head><meta property="og:title" content="GitHub - e2b-dev/infra: Infrastructure that's powering E2B Cloud.">
      <meta property="og:site_name" content="GitHub"></head>
      """

    let preview = PageMeta.preview(html: html, at: Self.repository)

    #expect(preview.title == "e2b-dev/infra")
    #expect(preview.site == "GitHub")
  }

  @Test func theSiteNameBeforeOrAfterATitleIsLeftToTheSiteLine() {
    func title(_ text: String) -> String? {
      let html = #"<head><meta property="og:site_name" content="The Verge"><title>"# + text + "</title></head>"
      return PageMeta.preview(html: html, at: URL(string: "https://www.theverge.com/a/b")!).title
    }

    #expect(title("Why microVMs won | The Verge") == "Why microVMs won")
    #expect(title("The Verge — Why microVMs won") == "Why microVMs won")
    #expect(title("Vergence: a study") == "Vergence: a study")
    #expect(title("The Verge") == "The Verge")
  }

  @Test func aPictureGivenRelativeToThePageIsMadeWhole() {
    let html = #"<head><meta property="og:image" content="/assets/card.png"></head>"#

    let preview = PageMeta.preview(html: html, at: Self.repository)

    #expect(preview.image == URL(string: "https://github.com/assets/card.png"))
  }

  @Test func aLinkIsFetchedOnceAndItsPictureComesFromThePreview() async {
    let network = FakeNetwork([
      Self.repository.absoluteString: .page(
        #"<head><meta property="og:title" content="infra"><meta property="og:image" content="/card.png"></head>"#),
      "https://github.com/card.png": .image("PNG"),
    ])
    let reader = LinkPreviewReader(network: network)

    let first = await reader.preview(of: Self.repository)
    let again = await reader.preview(of: Self.repository)
    let picture = await reader.image(of: Self.repository)

    #expect(first == again)
    #expect(first.title == "infra")
    #expect(picture == Data("PNG".utf8))
    #expect(network.requests.map(\.absoluteString) == [Self.repository.absoluteString, "https://github.com/card.png"])
  }

  @Test func aLinkThatCannotBeFetchedHasOnlyItsSite() async {
    let reader = LinkPreviewReader(network: FakeNetwork([:]))

    let preview = await reader.preview(of: Self.repository)

    #expect(preview == LinkPreview(url: Self.repository, title: nil, site: "github.com", summary: nil, image: nil))
    #expect(await reader.image(of: Self.repository) == nil)
  }

  @Test func aPictureIsReadByItsAddressOnce() async throws {
    let picture = try #require(URL(string: "https://example.com/cover.jpg"))
    let network = FakeNetwork(["https://example.com/cover.jpg": .image("JPEG", type: "image/jpeg")])
    let reader = LinkPreviewReader(network: network)

    let first = await reader.picture(at: picture)
    let again = await reader.picture(at: picture)

    #expect(first == Data("JPEG".utf8))
    #expect(again == first)
    #expect(network.requests == [picture])
  }

  @Test func onlyAnImageSmallEnoughIsAPicture() async throws {
    let page = try #require(URL(string: "https://example.com/page"))
    let large = try #require(URL(string: "https://example.com/large.png"))
    let missing = try #require(URL(string: "https://example.com/missing.png"))
    let local = URL(filePath: "/etc/hosts")
    let network = FakeNetwork([
      "https://example.com/page": .page("<html></html>"),
      "https://example.com/large.png": .image(String(repeating: "x", count: LinkPreviewReader.largestPicture + 1)),
      "https://example.com/missing.png": FakeNetwork.Answer(status: 404, type: "image/png", body: Data("PNG".utf8)),
    ])
    let reader = LinkPreviewReader(network: network)

    #expect(await reader.picture(at: page) == nil)
    #expect(await reader.picture(at: large) == nil)
    #expect(await reader.picture(at: missing) == nil)
    #expect(await reader.picture(at: local) == nil)
    #expect(!network.requests.contains(local))
  }
}
