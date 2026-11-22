import CoreGraphics
import CoreText
import Foundation
import LociModel
import Testing

@testable import LociMedia

struct SourceAcquisitionTests {
  @Test func aGitHubFileReturnsUnmodifiedTextFromTheRawRoute() async throws {
    let link = try #require(URL(string: "https://github.com/o/r/blob/topic/a%20b.swift?plain=1#L4"))
    let expected = try #require(URL(string: "https://github.com/o/r/raw/topic/a%20b.swift"))
    let reader = SourceTextReader(network: SourceNetwork(status: 200, text: "\nlet value = 42", expected: expected))

    #expect(try await reader.read(link) == "\nlet value = 42")
  }

  @Test func aMissingFileReportsTheHttpStatus() async throws {
    let link = try #require(URL(string: "https://raw.githubusercontent.com/o/r/main/missing"))
    let reader = SourceTextReader(network: SourceNetwork(status: 404, text: "", expected: link))
    await #expect(throws: FetchError(reason: "The page does not exist (HTTP 404).", cause: .unavailable)) {
      try await reader.read(link)
    }
  }

  @Test func readingAnArxivLinkPrintsTheTextFromEveryPdfPage() async throws {
    let url = try #require(URL(string: "https://arxiv.org/abs/1706.03762"))
    let address = "https://arxiv.org/pdf/1706.03762"
    let pdf = try Self.pdf(pages: ["First page", "Last page"])
    let reader = SourceTextReader(network: FakeNetwork([address: .pdf(pdf)]))

    let text = try await reader.read(url)

    #expect(text.contains("First page"))
    #expect(text.contains("Last page"))
  }

  @Test func aPdfWithoutTextExplainsWhyItCannotBeRead() async throws {
    let url = try #require(URL(string: "https://example.com/scanned.pdf"))
    let reader = SourceTextReader(network: FakeNetwork([url.absoluteString: .pdf(PaperFetcherTests.pdf(title: nil))]))

    await #expect(throws: FetchError(reason: "The PDF has no extractable text.")) { try await reader.read(url) }
  }

  private static func pdf(pages: [String]) throws -> Data {
    let data = NSMutableData()
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    var box = CGRect(x: 0, y: 0, width: 500, height: 500)
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
    for text in pages {
      context.beginPDFPage(nil)
      context.textPosition = CGPoint(x: 50, y: 450)
      let string = NSAttributedString(
        string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
      CTLineDraw(CTLineCreateWithAttributedString(string), context)
      context.endPDFPage()
    }
    context.closePDF()
    return data as Data
  }

  @Test func aRepoFetchesAndChecksOutOnlyTheRequestedCommit() async throws {
    let link = try #require(URL(string: "https://example.com/o/r"))
    let sha = try #require(CommitID(String(repeating: "a", count: 40)))
    let program = SourceProgram { call in
      .init(status: 0, output: call.arguments.contains("rev-parse") ? "\(sha)\n" : "")
    }
    let git = GitRepository(runner: program, executable: URL(filePath: "/test/git"))
    let folder = URL(filePath: "/cache/repo", directoryHint: .isDirectory)

    try await git.checkout(link, commit: sha, into: folder)

    let calls = await program.calls
    let fetch = try #require(calls.first { $0.arguments.contains("fetch") })
    #expect(fetch.arguments.contains("--depth=1"))
    #expect(fetch.arguments.suffix(2) == [link.absoluteString, sha.description])
    #expect(calls.contains { $0.arguments.contains("--detach") && $0.arguments.contains(sha.description) })
    #expect(calls.allSatisfy { $0.executable == URL(filePath: "/test/git") })
  }

  @Test func anUnpinnedRepoResolvesTheRemoteDefaultHead() async throws {
    let link = try #require(URL(string: "https://example.com/o/r"))
    let sha = try #require(CommitID(String(repeating: "b", count: 40)))
    let program = SourceProgram { _ in .init(status: 0, output: "\(sha)\tHEAD\n") }
    let git = GitRepository(runner: program, executable: URL(filePath: "/test/git"))
    #expect(try await git.head(of: link) == sha)
  }

  @Test func aPrivateOrMissingRepoReportsWhyItCannotBeFetched() async throws {
    let link = try #require(URL(string: "https://github.com/o/r"))
    let program = SourceProgram { _ in .init(status: 128, output: "", diagnostics: "remote: Repository not found.") }
    let git = GitRepository(runner: program, executable: URL(filePath: "/test/git"))
    await #expect(throws: FetchError(reason: "The repository was not found or is private.")) {
      try await git.head(of: link)
    }
  }
}

private struct SourceNetwork: Network {
  let status: Int
  let text: String
  let expected: URL

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    #expect(request.url == expected)
    guard let response = HTTPURLResponse(url: expected, statusCode: status, httpVersion: nil, headerFields: nil) else {
      throw FetchError(reason: "invalid test response")
    }
    return (Data(text.utf8), response)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "unexpected download")
  }
}

private actor SourceProgram: ProgramRunner {
  private let reply: @Sendable (ProgramCall) -> ProgramResult
  private(set) var calls: [ProgramCall] = []

  init(_ reply: @escaping @Sendable (ProgramCall) -> ProgramResult) { self.reply = reply }

  func run(_ call: ProgramCall, line: @escaping @Sendable (String) -> Void) async throws(ProgramError) -> ProgramResult
  {
    calls.append(call)
    return reply(call)
  }
}
