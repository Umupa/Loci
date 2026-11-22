import Foundation
import LociModel

/// The app's `TextFetching`: articles are read in a web view that is never shown, with defuddle; papers are
/// fetched as PDFs.
public struct WebTextFetcher: TextFetching {
  private let network: any Network
  private let timeout: Duration

  /// `timeout` bounds loading and reading a page; images are fetched after it.
  public init(network: any Network, timeout: Duration = .seconds(15)) {
    self.network = network
    self.timeout = timeout
  }

  public func article(at url: URL, html: String? = nil) async throws(FetchError) -> FetchedArticle {
    try await articlePage(at: url, html: html).article()
  }

  public func articlePage(at url: URL, html: String?) async throws(FetchError) -> ArticlePage {
    let assembler = ArticleAssembler(network: network)
    let source: PageReader.Source = html.map { .html($0, base: url) } ?? .url(url)
    let reader = try await PageReader.open(source, timeout: timeout)
    let address = await reader.address
    let head = await reader.head()
    return ArticlePage(
      preview: PageMeta.preview(html: head, at: address), coverImages: PageMeta.coverImages(html: head, at: address)
    ) { () async throws(FetchError) in
      do throws(FetchError) {
        return try await assembler.article(from: reader.extract(), at: address)
      } catch {
        guard html != nil, !Task.isCancelled else { throw error }
        return try await article(at: url)
      }
    }
  }

  public func paper(at url: URL) async throws(FetchError) -> FetchedPaper {
    try await PaperFetcher(network: network).paper(at: url)
  }
}
