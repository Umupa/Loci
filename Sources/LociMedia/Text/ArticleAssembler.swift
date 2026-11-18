import Foundation
import LociModel

/// Turns what defuddle found on a page into an article that reads offline: the images it shows are fetched
/// and the text points at them as `images/<name>`.
struct ArticleAssembler: Sendable {
  let network: any Network

  static let imageFolder = "images"

  func article(from extraction: Extraction, at page: URL) async throws(FetchError) -> FetchedArticle {
    let body = extraction.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { throw FetchError(reason: "The page has no text to read.") }
    let (markdown, images) = await localizingImages(in: body, from: page)
    return FetchedArticle(
      title: Self.title(of: extraction, at: page), authors: Self.authors(extraction.author),
      site: Self.nonEmpty(extraction.site), published: Self.date(extraction.published),
      language: Self.language(extraction.language), markdown: markdown, images: images)
  }

  /// Fetches each remote image once, all at the same time. An image that cannot be fetched keeps its remote
  /// address, so one missing picture does not cost the whole article.
  private func localizingImages(in markdown: String, from page: URL) async -> (String, [FetchedFile]) {
    var addresses: [String: URL] = [:]
    for address in Self.imageAddresses(in: markdown) {
      if let url = URL(string: address, relativeTo: page)?.absoluteURL, url.isWebLink { addresses[address] = url }
    }
    let fetched = await withTaskGroup(of: (String, FetchedFile?).self) { group in
      for (address, url) in addresses {
        group.addTask { (address, await image(at: url, referer: page)) }
      }
      var fetched: [String: FetchedFile] = [:]
      for await (address, file) in group {
        if let file { fetched[address] = file }
      }
      return fetched
    }
    var files: [FetchedFile] = []
    for file in fetched.values.sorted(by: { $0.name < $1.name }) where !files.contains(where: { $0.name == file.name })
    {
      files.append(file)
    }
    let local = fetched.mapValues(\.name)
    func rewritten(_ address: Substring) -> String? { local[String(address)].map { "\(Self.imageFolder)/\($0)" } }
    let result = markdown.replacing(Self.markdownImage) { match in
      guard let name = rewritten(match.output.1) else { return String(match.output.0) }
      return String(match.output.0).replacing(String(match.output.1), with: name, maxReplacements: 1)
    }.replacing(Self.imageTag) { match in
      guard let name = rewritten(match.output.1) else { return String(match.output.0) }
      return String(match.output.0).replacing("src=\"\(match.output.1)\"", with: "src=\"\(name)\"")
    }
    return (result, files)
  }

  private func image(at url: URL, referer: URL) async -> FetchedFile? {
    var request = URLRequest(url: url)
    request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
    guard let (data, response) = try? await network.data(for: request), (200..<300).contains(response.statusCode),
      !data.isEmpty, let type = response.mimeType, type.hasPrefix("image/")
    else { return nil }
    return FetchedFile(name: Self.fileName(for: url, type: type), data: data)
  }

  private static var markdownImage: Regex<(Substring, Substring)> {
    /!\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/
  }
  private static var imageTag: Regex<(Substring, Substring)> { /<img[^>]*?\ssrc="([^"]+)"/ }

  /// The addresses of the images in Markdown image syntax and in `<img>` tags, in order of appearance.
  static func imageAddresses(in markdown: String) -> [String] {
    let markdownImages = markdown.matches(of: markdownImage)
      .map { (String($0.output.1), $0.range.lowerBound) }
    let tags = markdown.matches(of: imageTag).map { (String($0.output.1), $0.range.lowerBound) }
    return (markdownImages + tags).sorted { $0.1 < $1.1 }.map(\.0).filter { !$0.hasPrefix("data:") }
  }

  /// A name that is the same for the same address, so an image linked twice is stored once.
  static func fileName(for url: URL, type: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in url.absoluteString.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0100_0000_01b3
    }
    let digits = String(hash, radix: 16)
    return String(repeating: "0", count: 16 - digits.count) + digits + "." + fileExtension(for: url, type: type)
  }

  private static func fileExtension(for url: URL, type: String) -> String {
    let subtype = type.dropFirst("image/".count).split(separator: ";").first.map(String.init) ?? ""
    switch subtype.lowercased() {
    case "jpeg", "jpg", "pjpeg": return "jpg"
    case "png", "gif", "webp", "avif", "bmp", "tiff", "heic": return subtype.lowercased()
    case "svg+xml": return "svg"
    case "x-icon", "vnd.microsoft.icon": return "ico"
    default:
      let fromPath = url.pathExtension.lowercased()
      return fromPath.isEmpty || fromPath.count > 5 ? "img" : fromPath
    }
  }

  static func title(of extraction: Extraction, at page: URL) -> String {
    nonEmpty(extraction.title) ?? nonEmpty(extraction.domain) ?? page.host() ?? page.absoluteString
  }

  /// Bylines name several people with commas, `and` or `、`.
  static func authors(_ byline: String) -> [String] {
    byline.split(separator: /\s*(?:,|;|、|，|\band\b|&)\s*/).map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// A full ISO 8601 moment, or a day alone; anything else is not a date to trust.
  static func date(_ text: String) -> Date? {
    let text = text.trimmingCharacters(in: .whitespaces)
    if let moment = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return moment }
    if let moment = try? Date.ISO8601FormatStyle().parse(text) { return moment }
    guard let day = text.prefixMatch(of: /(\d{4})-(\d\d)-(\d\d)/) else { return nil }
    return try? Date.ISO8601FormatStyle().parse("\(day.1)-\(day.2)-\(day.3)T00:00:00Z")
  }

  /// A BCP 47 tag as an item takes it; a page's `en_US` is read as `en-US`.
  static func language(_ text: String) -> String? {
    let tag = text.trimmingCharacters(in: .whitespaces).replacing("_", with: "-")
    return tag.wholeMatch(of: /[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*/) == nil ? nil : tag
  }

  private static func nonEmpty(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
