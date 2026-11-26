/// Has a model tidy an article: what the site put around the text goes, headings, code and captions are set
/// right, and the tidied text replaces the original, which is not kept. A translation made from the original no
/// longer fits and is made again.
public struct TidyArticle: RemoteCommand {
  public static let name = "library.tidyArticle"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.tidyArticle(item)
  }
}

/// How tidying an article is going; `nil` on the page when it is not being tidied.
public enum TidyProgress: Hashable, Codable, Sendable {
  /// The share of the pieces tidied so far; the article is replaced only once all are.
  case running(Fraction)
  /// What went wrong; the article is as it was.
  case failed(String)
}
