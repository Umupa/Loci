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
    let assembler = ArticleAssembler(network: network)
    if let html, let extraction = try? await PageReader.read(.html(html, base: url), timeout: timeout),
      let article = try? await assembler.article(from: extraction, at: url)
    {
      return article
    }
    let extraction = try await PageReader.read(.url(url), timeout: timeout)
    return try await assembler.article(from: extraction, at: url)
  }

  public func paper(at url: URL) async throws(FetchError) -> FetchedPaper {
    try await PaperFetcher(network: network).paper(at: url)
  }
}
