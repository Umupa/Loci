import Foundation
import LociModel

/// Fetches a paper's PDF. An arXiv link is turned into its PDF and arXiv's own title and authors; any other
/// link is fetched as it is and described by the PDF itself or its file name.
struct PaperFetcher: Sendable {
  let network: any Network

  func paper(at url: URL) async throws(FetchError) -> FetchedPaper {
    if let arxiv = ArxivID(url) {
      let pdf = try await self.pdf(at: arxiv.pdf)
      let entry = try? await self.entry(for: arxiv)
      let info = PDFInfo(pdf)
      return FetchedPaper(
        title: entry?.title ?? info?.title ?? "arXiv \(arxiv.value)", authors: entry?.authors ?? info?.authors ?? [],
        published: entry?.published, pdf: pdf)
    }
    let pdf = try await self.pdf(at: url)
    let info = PDFInfo(pdf)
    return FetchedPaper(
      title: info?.title ?? PDFInfo.title(fromFileIn: url), authors: info?.authors ?? [], published: nil, pdf: pdf)
  }

  private func pdf(at url: URL) async throws(FetchError) -> Data {
    let (data, response) = try await network.data(for: URLRequest(url: url))
    if let failure = PageReader.failure(status: response.statusCode) { throw failure }
    guard data.starts(with: Data("%PDF-".utf8)) else {
      throw FetchError(reason: "The link did not lead to a PDF; the site may want you to sign in.", needsLogin: true)
    }
    return data
  }

  private func entry(for arxiv: ArxivID) async throws(FetchError) -> ArxivEntry? {
    let (data, response) = try await network.data(for: URLRequest(url: arxiv.metadata))
    guard (200..<300).contains(response.statusCode) else { return nil }
    return ArxivEntry(atom: data)
  }
}

/// An arXiv paper's identifier, with or without a version: `2401.12345v2` or `cs/0101001`.
struct ArxivID: Hashable, Sendable {
  let value: String
  let pdf: URL
  /// arXiv's Atom answer describing the paper.
  let metadata: URL

  init?(_ url: URL) {
    let host = (url.host() ?? "").lowercased()
    guard host == "arxiv.org" || host.hasSuffix(".arxiv.org") else { return nil }
    let path = url.path()
    guard let prefix = ["/abs/", "/pdf/"].first(where: path.hasPrefix) else { return nil }
    var id = String(path.dropFirst(prefix.count))
    if id.hasSuffix(".pdf") { id.removeLast(4) }
    while id.hasSuffix("/") { id.removeLast() }
    guard id.wholeMatch(of: /[A-Za-z\-.]*\/?[0-9.]+(v[0-9]+)?/) != nil,
      let pdf = URL(string: "https://arxiv.org/pdf/\(id)"),
      let metadata = URL(string: "https://export.arxiv.org/api/query?id_list=\(id)")
    else { return nil }
    value = id
    self.pdf = pdf
    self.metadata = metadata
  }
}
