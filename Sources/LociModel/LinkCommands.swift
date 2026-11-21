import Foundation

/// What a web page says about itself for a card that links to it: its Open Graph title, picture, site and
/// description, or what stands in for them.
public struct LinkPreview: Codable, Hashable, Sendable {
  public let url: URL
  /// `nil` when the page could not be read or names nothing.
  public let title: String?
  /// The site as it names itself, else its domain.
  public let site: String
  public let summary: String?
  /// The page's picture, which `ReadLinkImage` fetches.
  public let image: URL?

  public init(url: URL, title: String?, site: String, summary: String?, image: URL?) {
    self.url = url
    self.title = title
    self.site = site
    self.summary = summary
    self.image = image
  }
}

/// What the page behind a link says about itself, fetched once and kept while the app runs. A page that
/// cannot be fetched gives a preview with only its site.
public struct ReadLinkPreview: Command {
  public static let name = "link.preview"
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> LinkPreview {
    try await handler.linkPreview(of: url)
  }
}

/// The picture of the page behind a link, as its preview names it; `nil` when it has none or it cannot be
/// fetched.
public struct ReadLinkImage: Command {
  public static let name = "link.image"
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Data? {
    try await handler.linkImage(of: url)
  }
}
