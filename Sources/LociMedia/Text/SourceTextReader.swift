import Foundation
import LociModel
import PDFKit

public struct SourceTextReader: Sendable {
  private let network: any Network
  private let timeout: Duration

  public init(network: any Network, timeout: Duration = .seconds(15)) {
    self.network = network
    self.timeout = timeout
  }

  public func read(_ url: URL) async throws(FetchError) -> String {
    if let raw = Self.rawFile(for: url) {
      let (data, response) = try await network.data(for: URLRequest(url: raw))
      if let failure = PageReader.failure(status: response.statusCode) { throw failure }
      guard let text = String(data: data, encoding: .utf8), !text.utf8.contains(0) else {
        throw FetchError(reason: "The GitHub file is not UTF-8 text.")
      }
      return text
    }
    if LinkKind(url) == .paper { return try await paperText(at: url) }
    switch try await PageReader.source(at: url, timeout: timeout) {
    case .page(let page):
      guard !page.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw FetchError(reason: "The page has no readable text.")
      }
      return page.markdown
    case .pdf(let address):
      return try await paperText(at: address)
    }
  }

  private func paperText(at url: URL) async throws(FetchError) -> String {
    let pdf = try await PaperFetcher(network: network).pdf(at: ArxivID(url)?.pdf ?? url)
    guard let document = PDFDocument(data: pdf) else {
      throw FetchError(reason: "The PDF could not be opened.")
    }
    guard let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw FetchError(reason: "The PDF has no extractable text.")
    }
    return text
  }

  public static func rawFile(for url: URL) -> URL? {
    guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    if let fragment = parts.percentEncodedFragment, !fragment.hasPrefix("/"), !fragment.hasPrefix("!") {
      parts.fragment = nil
    }
    switch parts.host?.lowercased() {
    case "raw.githubusercontent.com":
      return parts.url
    case "github.com", "www.github.com":
      var pieces = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
      guard pieces.count >= 6, pieces[3] == "blob" || pieces[3] == "raw" else { return nil }
      pieces[3] = "raw"
      parts.percentEncodedPath = pieces.joined(separator: "/")
      parts.query = nil
      return parts.url
    default:
      return nil
    }
  }
}
