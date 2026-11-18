import Foundation
import LociMedia
import LociModel
import Testing

/// Real pages over the real network. Skipped unless `LOCI_TEXT_LIVE=1`; each page is timed against the five
/// seconds L-S1 allows and the start of its text is printed so its cleanliness can be checked by eye.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_TEXT_LIVE"] == "1"))
@MainActor
struct TextLiveTests {
  nonisolated static let articles = [
    "https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/",
    "https://blog.cloudflare.com/how-we-built-pingora-the-proxy-that-connects-cloudflare-to-the-internet/",
    "https://medium.com/@karpathy/software-2-0-a64152b37c35",
    "https://newsletter.pragmaticengineer.com/p/how-kubernetes-is-built-with-kat",
    "https://www.infoq.cn/article/X8xujm6xovp7z2YzWbpM",
    "https://martinfowler.com/articles/patterns-of-distributed-systems/",
    "https://jvns.ca/blog/2023/08/03/behind--hello-world/",
    "https://go.dev/blog/pgo",
    "https://www.brendangregg.com/blog/2024-03-17/the-return-of-the-frame-pointers.html",
    "https://react.dev/learn/thinking-in-react",
  ]

  @Test(arguments: articles)
  func anArticleIsReadWithinFiveSeconds(_ link: String) async throws {
    let fetcher = WebTextFetcher(network: LiveNetwork())
    let clock = ContinuousClock()
    let started = clock.now
    let article = try await fetcher.article(at: URL(string: link)!)
    let elapsed = clock.now - started
    let preview = String(article.markdown.prefix(400)).replacing("\n", with: " ⏎ ")
    Issue.record(
      """
      LIVE \(link)
        \(elapsed) · \(article.markdown.count) chars · \(article.images.count) images · \
      title “\(article.title)” · authors \(article.authors) · site \(article.site ?? "-") · \
      language \(article.language ?? "-") · published \(article.published.map { "\($0)" } ?? "-")
        \(preview)
      """, severity: .warning)
    #expect(article.markdown.count > 500)
    #expect(elapsed < .seconds(5))
  }

  @Test func anArxivPaperComesWithItsTitleAndAuthors() async throws {
    let paper = try await WebTextFetcher(network: LiveNetwork()).paper(
      at: URL(string: "https://arxiv.org/abs/1706.03762")!)
    Issue.record("LIVE arXiv “\(paper.title)” · \(paper.authors) · \(paper.pdf.count) bytes", severity: .warning)
    #expect(paper.title == "Attention Is All You Need")
    #expect(paper.authors.first == "Ashish Vaswani")
    #expect(paper.pdf.starts(with: Data("%PDF-".utf8)))
  }
}

/// The smallest real `Network`, for live tests only; the app's own lives with the media fetchers.
struct LiveNetwork: Network {
  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw FetchError(reason: "not HTTP") }
      return (data, http)
    } catch let error as FetchError {
      throw error
    } catch {
      throw FetchError(reason: error.localizedDescription)
    }
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "not used in these tests")
  }
}
