import CoreGraphics
import Foundation
import LociMedia
import Testing

@testable import LociMedia

struct PaperFetcherTests {
  static let atom = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>ArXiv Query: id_list=1706.03762</title>
      <entry>
        <id>http://arxiv.org/abs/1706.03762v7</id>
        <published>2017-06-12T17:57:34Z</published>
        <title>Attention Is All
          You Need</title>
        <author><name>Ashish Vaswani</name></author>
        <author><name>Noam Shazeer</name></author>
      </entry>
    </feed>
    """

  /// A one-page PDF whose document information names a title and an author.
  static func pdf(title: String?, author: String? = nil) -> Data {
    let data = NSMutableData()
    var info: [CFString: Any] = [:]
    if let title { info[kCGPDFContextTitle] = title }
    if let author { info[kCGPDFContextAuthor] = author }
    var box = CGRect(x: 0, y: 0, width: 100, height: 100)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)
    else { return Data() }
    context.beginPDFPage(nil)
    context.endPDFPage()
    context.closePDF()
    return data as Data
  }

  @Test(arguments: [
    "https://arxiv.org/abs/1706.03762", "https://arxiv.org/pdf/1706.03762", "https://arxiv.org/pdf/1706.03762.pdf",
    "https://www.arxiv.org/abs/1706.03762/",
  ])
  func everyFormOfAnArxivLinkLeadsToTheSamePaper(_ link: String) throws {
    let id = try #require(ArxivID(URL(string: link)!))
    #expect(id.value == "1706.03762")
    #expect(id.pdf.absoluteString == "https://arxiv.org/pdf/1706.03762")
  }

  @Test func versionsAndOldStyleIdentifiersAreKept() throws {
    #expect(ArxivID(URL(string: "https://arxiv.org/abs/2401.12345v2")!)?.value == "2401.12345v2")
    #expect(ArxivID(URL(string: "https://arxiv.org/abs/cs/0101001")!)?.value == "cs/0101001")
    #expect(ArxivID(URL(string: "https://arxiv.org/list/cs.AI/recent")!) == nil)
  }

  @Test func anArxivPaperHasArxivsTitleAuthorsAndDate() async throws {
    let pdf = Self.pdf(title: "Something else")
    let network = FakeNetwork([
      "https://arxiv.org/pdf/1706.03762": .pdf(pdf),
      "https://export.arxiv.org/api/query?id_list=1706.03762": .atom(Self.atom),
    ])
    let paper = try await PaperFetcher(network: network).paper(at: URL(string: "https://arxiv.org/abs/1706.03762")!)

    #expect(paper.title == "Attention Is All You Need")
    #expect(paper.authors == ["Ashish Vaswani", "Noam Shazeer"])
    #expect(paper.published == Date(timeIntervalSince1970: 1_497_290_254))
    #expect(paper.pdf == pdf)
  }

  @Test func anArxivPaperWhoseDescriptionCannotBeHadIsDescribedByItsPDF() async throws {
    let network = FakeNetwork([
      "https://arxiv.org/pdf/1706.03762": .pdf(Self.pdf(title: "Attention", author: "A. Vaswani; N. Shazeer"))
    ])
    let paper = try await PaperFetcher(network: network).paper(at: URL(string: "https://arxiv.org/abs/1706.03762")!)

    #expect(paper.title == "Attention")
    #expect(paper.authors == ["A. Vaswani", "N. Shazeer"])
  }

  @Test func aPDFLinkIsNamedByTheTitleInsideIt() async throws {
    let url = URL(string: "https://example.com/files/raft.pdf")!
    let network = FakeNetwork([url.absoluteString: .pdf(Self.pdf(title: "In Search of an Understandable Consensus"))])
    let paper = try await PaperFetcher(network: network).paper(at: url)

    #expect(paper.title == "In Search of an Understandable Consensus")
    #expect(paper.published == nil)
  }

  @Test func aPDFWithAWordProcessorsTitleIsNamedByItsFile() async throws {
    let url = URL(string: "https://example.com/files/paxos_made-simple.pdf")!
    let network = FakeNetwork([url.absoluteString: .pdf(Self.pdf(title: "Microsoft Word - paxos.doc"))])

    #expect(try await PaperFetcher(network: network).paper(at: url).title == "paxos made simple")
  }

  @Test func aLinkThatGivesAPageInsteadOfAPDFWantsASignIn() async throws {
    let url = URL(string: "https://journal.example.com/paper.pdf")!
    let network = FakeNetwork([url.absoluteString: .page("<html>Sign in</html>")])

    await #expect(
      throws: FetchError(reason: "The link did not lead to a PDF; the site may want you to sign in.", needsLogin: true)
    ) {
      try await PaperFetcher(network: network).paper(at: url)
    }
  }

  @Test func aRefusedOrMissingPDFSaysSo() async throws {
    let refused = URL(string: "https://example.com/a.pdf")!
    let missing = URL(string: "https://example.com/b.pdf")!
    let network = FakeNetwork([
      refused.absoluteString: .pdf(Data(), status: 403), missing.absoluteString: .pdf(Data(), status: 404),
    ])

    await #expect(throws: FetchError(reason: "The site refused the page (HTTP 403).", needsLogin: true)) {
      try await PaperFetcher(network: network).paper(at: refused)
    }
    await #expect(throws: FetchError(reason: "The page does not exist (HTTP 404).", cause: .unavailable)) {
      try await PaperFetcher(network: network).paper(at: missing)
    }
  }

  @Test func anEmptyFeedHasNoEntry() {
    #expect(ArxivEntry(atom: Data("<feed xmlns=\"http://www.w3.org/2005/Atom\"></feed>".utf8)) == nil)
  }
}
