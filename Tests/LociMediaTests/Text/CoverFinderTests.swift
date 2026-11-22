import Foundation
import LociModel
import Testing

@testable import LociMedia

struct CoverFinderTests {
  @Test func aCoverUsesOpenGraphBeforeTwitterAndFallsBackWhenItCannotBeRead() async throws {
    let site = try #require(URL(string: "https://example.com/story"))
    let html = """
      <head><meta property="og:image" content="/bad.png"><meta name="twitter:image" content="/large.png"></head>
      """
    let network = CoverNetwork()
    let cover = await CoverFinder(network: network).first(at: PageMeta.coverImages(html: html, at: site), referer: site)
    #expect(cover?.data == Self.picture(width: 300, height: 300))
    #expect(await network.paths == ["/bad.png", "/large.png"])
  }

  @Test func theFirstBodyImageWithBothSidesAtLeast300PixelsIsTheCover() async throws {
    let site = try #require(URL(string: "https://example.com/story"))
    let network = CoverNetwork()
    let cover = await CoverFinder(network: network).body(
      markdown: "![](/narrow.png)\n\n![](/large.png)\n\n![](/later.png)", at: site
    ) { _ in nil }
    #expect(cover?.data == Self.picture(width: 300, height: 300))
    #expect(await network.paths == ["/narrow.png", "/large.png"])
  }

  @Test func lookingUpAnAppleEpisodeUsesTheShowsIdentifierAndArtwork() async throws {
    let site = try #require(URL(string: "https://podcasts.apple.com/us/podcast/show/id1234?i=900"))
    let network = CoverNetwork()
    let cover = await CoverFinder(network: network).podcast(at: site)
    #expect(cover?.data == Self.picture(width: 300, height: 300))
    #expect(await network.paths == ["/lookup?id=1234&country=us", "/large.png"])
  }

  fileprivate static func picture(width: Int, height: Int) -> Data {
    var data = Data("P6\n\(width) \(height)\n255\n".utf8)
    data.append(Data(repeating: 0xAF, count: width * height * 3))
    return data
  }
}

private actor CoverNetwork: Network {
  private(set) var paths: [String] = []

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    guard let url = request.url else { throw FetchError(reason: "Missing address.") }
    paths.append(url.path() + (url.query().map { "?" + $0 } ?? ""))
    let (data, type): (Data, String) =
      switch url.path() {
      case "/lookup":
        (
          Data(
            """
            {"results":[{"kind":"podcast","trackId":1234,"artworkUrl100":"https://example.com/large.png"}]}
            """.utf8), "application/json"
        )
      case "/bad.png": (Data(), "image/png")
      case "/narrow.png": (CoverFinderTests.picture(width: 299, height: 800), "image/x-portable-pixmap")
      default: (CoverFinderTests.picture(width: 300, height: 300), "image/x-portable-pixmap")
      }
    guard
      let response = HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])
    else { throw FetchError(reason: "Missing response.") }
    return (data, response)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (LociModel.Fraction?) -> Void)
    async throws(FetchError) -> URL
  {
    throw FetchError(reason: "Unexpected download.")
  }
}
