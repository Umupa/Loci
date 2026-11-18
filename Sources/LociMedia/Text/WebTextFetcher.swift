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

  public func article(at url: URL) async throws(FetchError) -> FetchedArticle {
    let extraction = try await PageReader.read(.url(url), timeout: timeout)
    return try await ArticleAssembler(network: network).article(from: extraction, at: url)
  }

  public func paper(at url: URL) async throws(FetchError) -> FetchedPaper {
    try await PaperFetcher(network: network).paper(at: url)
  }
}
