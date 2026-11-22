import Foundation
import ImageIO
import LociModel
import UniformTypeIdentifiers

public struct CoverFinder: Sendable {
  private let network: any Network

  public init(network: any Network) {
    self.network = network
  }

  public func first(at addresses: [URL], referer: URL? = nil) async -> FetchedFile? {
    for url in addresses {
      if let data = await picture(at: url, referer: referer), let file = Self.cover(data) { return file }
    }
    return nil
  }

  public func webpage(at url: URL, includeBody: Bool = false) async -> FetchedFile? {
    guard url.isWebLink, !Task.isCancelled, let (data, response) = try? await network.data(for: Self.request(url)),
      (200..<300).contains(response.statusCode), response.mimeType == "text/html"
    else { return nil }
    let address = response.url ?? url
    return await first(
      at: PageMeta.coverImages(html: String(decoding: data, as: UTF8.self), at: address), referer: address)
  }

  public func body(
    markdown: String, at page: URL?, localImage: (String) -> Data?
  ) async -> FetchedFile? {
    var seen: Set<String> = []
    for address in ArticleAssembler.imageAddresses(in: markdown) where seen.insert(address).inserted {
      let data: Data?
      if address.hasPrefix("images/") {
        data = localImage(String(address.dropFirst("images/".count)))
      } else if let url = URL(string: address, relativeTo: page)?.absoluteURL {
        data = await picture(at: url, referer: page)
      } else {
        continue
      }
      if let data, let file = Self.cover(data, minimum: 300) { return file }
    }
    return nil
  }

  public func podcast(at episode: URL) async -> FetchedFile? {
    guard episode.host()?.lowercased() == "podcasts.apple.com",
      let id = episode.pathComponents.last?.wholeMatch(of: /id([0-9]+)/).flatMap({ Int($0.1) })
    else { return nil }
    var lookup = URLComponents()
    lookup.scheme = "https"
    lookup.host = "itunes.apple.com"
    lookup.path = "/lookup"
    lookup.queryItems = [URLQueryItem(name: "id", value: String(id))]
    if let country = episode.pathComponents.dropFirst().first, country.wholeMatch(of: /[a-zA-Z]{2}/) != nil {
      lookup.queryItems?.append(URLQueryItem(name: "country", value: country.lowercased()))
    }
    guard let url = lookup.url, let (data, response) = try? await network.data(for: Self.request(url)),
      (200..<300).contains(response.statusCode), let result = try? JSONDecoder().decode(Lookup.self, from: data),
      let show = result.results.first(where: { $0.kind == "podcast" && $0.trackId == id })
    else { return nil }
    return await first(at: [show.artworkUrl600, show.artworkUrl100, show.artworkUrl60].compactMap { $0 })
  }

  private struct Lookup: Decodable {
    let results: [Show]

    struct Show: Decodable {
      let kind: String?
      let trackId: Int?
      let artworkUrl600: URL?
      let artworkUrl100: URL?
      let artworkUrl60: URL?
    }
  }

  private func picture(at url: URL, referer: URL?) async -> Data? {
    guard url.isWebLink, !Task.isCancelled else { return nil }
    var request = Self.request(url)
    request.setValue(referer?.absoluteString, forHTTPHeaderField: "Referer")
    guard let (data, response) = try? await network.data(for: request),
      (200..<300).contains(response.statusCode), response.mimeType?.hasPrefix("image/") == true
    else { return nil }
    return data
  }

  private static func request(_ url: URL) -> URLRequest {
    URLRequest(url: url, timeoutInterval: 15)
  }

  private static func cover(_ data: Data, minimum: Int = 1) -> FetchedFile? {
    guard !data.isEmpty, data.count <= LinkPreviewReader.largestPicture,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let type = CGImageSourceGetType(source), let fileExtension = UTType(type as String)?.preferredFilenameExtension,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
      let width = properties[kCGImagePropertyPixelWidth as String] as? Int, width >= minimum,
      let height = properties[kCGImagePropertyPixelHeight as String] as? Int, height >= minimum,
      CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
    else { return nil }
    return FetchedFile(name: "cover.\(fileExtension)", data: data)
  }
}
