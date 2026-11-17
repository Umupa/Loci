import Foundation

/// A web page reduced to its text, ready to become an article item.
public struct FetchedArticle: Sendable {
  public let title: String
  public let authors: [String]
  /// The site as it names itself.
  public let site: String?
  public let published: Date?
  /// A BCP 47 tag, when the page declares one.
  public let language: String?
  /// Image references point at `images` by file name, so the text reads offline.
  public let markdown: String
  public let images: [FetchedFile]

  public init(
    title: String, authors: [String], site: String?, published: Date?, language: String?, markdown: String,
    images: [FetchedFile]
  ) {
    self.title = title
    self.authors = authors
    self.site = site
    self.published = published
    self.language = language
    self.markdown = markdown
    self.images = images
  }
}

/// A paper's PDF with what could be told about it.
public struct FetchedPaper: Sendable {
  public let title: String
  public let authors: [String]
  public let published: Date?
  public let pdf: Data

  public init(title: String, authors: [String], published: Date?, pdf: Data) {
    self.title = title
    self.authors = authors
    self.published = published
    self.pdf = pdf
  }
}

/// A file fetched alongside the main content, named as the content refers to it.
public struct FetchedFile: Sendable {
  public let name: String
  public let data: Data

  public init(name: String, data: Data) {
    self.name = name
    self.data = data
  }
}

/// Why a link could not be fetched, in words the reader can act on.
public struct FetchError: Error, Sendable, Equatable {
  public let reason: String
  /// The site wants a signed-in visitor.
  public let needsLogin: Bool

  public init(reason: String, needsLogin: Bool = false) {
    self.reason = reason
    self.needsLogin = needsLogin
  }
}

/// Fetches the text behind article and paper links. The app's version loads the page in a web view that
/// is never shown, so pages that need JavaScript and the built-in browser's logins both work.
public protocol TextFetching: Sendable {
  func article(at url: URL) async throws(FetchError) -> FetchedArticle
  func paper(at url: URL) async throws(FetchError) -> FetchedPaper
}
