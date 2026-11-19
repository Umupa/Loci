/// An article in another language, passage by passage; the contents of `translations/<language>.json` beside
/// `content.md`. Each passage keeps the Markdown it was made from, so a passage whose original has changed since
/// finds no translation instead of a wrong one.
public struct ArticleTranslation: Hashable, Codable, Sendable {
  /// A BCP 47 tag.
  public let language: String
  public let passages: [Passage]

  public struct Passage: Hashable, Codable, Sendable {
    /// The original passage's Markdown.
    public let source: String
    /// Its translation, in Markdown.
    public let text: String

    public init(source: String, text: String) {
      self.source = source
      self.text = text
    }
  }

  public init(language: String, passages: [Passage]) throws {
    self.language = try language.requiringText("language")
    self.passages = passages
  }

  /// Translations by the Markdown they were made from.
  public var bySource: [String: String] {
    Dictionary(passages.map { ($0.source, $0.text) }, uniquingKeysWith: { _, latest in latest })
  }
}

/// How translating an article is going; `nil` on the page when it is not being translated.
public enum TranslationProgress: Hashable, Codable, Sendable {
  /// The share of the passages translated so far.
  case running(Fraction)
  /// What went wrong; asking again carries on from the passages already translated.
  case failed(String)
}
