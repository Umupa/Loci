/// An item with its text, as one view shows it.
public struct ItemPage: Hashable, Codable, Sendable {
  public let item: Item
  /// The text of an article or paper; `nil` for kinds read some other way.
  public let text: String?
  /// Whether the article is in a language other than the reader's, so it can be translated.
  public let translatable: Bool
  /// The article in the reader's language, as far as it has been translated.
  public let translation: ArticleTranslation?
  public let translating: TranslationProgress?
  public let tidying: TidyProgress?

  public init(
    item: Item, text: String?, translatable: Bool = false, translation: ArticleTranslation? = nil,
    translating: TranslationProgress? = nil, tidying: TidyProgress? = nil
  ) {
    self.item = item
    self.text = text
    self.translatable = translatable
    self.translation = translation
    self.translating = translating
    self.tidying = tidying
  }

  private enum CodingKeys: String, CodingKey {
    case item, text, translatable, translation, translating, tidying
  }

  /// A Mac on an older version sends no translation or tidying fields; its articles read as not translatable and
  /// not being tidied.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    item = try container.decode(Item.self, forKey: .item)
    text = try container.decodeIfPresent(String.self, forKey: .text)
    translatable = try container.decodeIfPresent(Bool.self, forKey: .translatable) ?? false
    translation = try container.decodeIfPresent(ArticleTranslation.self, forKey: .translation)
    translating = try container.decodeIfPresent(TranslationProgress.self, forKey: .translating)
    tidying = try container.decodeIfPresent(TidyProgress.self, forKey: .tidying)
  }
}

/// Whether the host's storage is sound, and which files it could not use.
public struct Health: Hashable, Codable, Sendable {
  public let database: DatabaseState
  /// The database was replaced when this host started, so reading positions were lost.
  public let readingStateLost: Bool
  public let fileProblems: [FileProblem]

  public init(database: DatabaseState, readingStateLost: Bool, fileProblems: [FileProblem]) {
    self.database = database
    self.readingStateLost = readingStateLost
    self.fileProblems = fileProblems
  }

  public enum DatabaseState: Hashable, Codable, Sendable {
    /// Lists and search may be out of date until the rebuild finishes.
    case rebuilding
    case ready
    /// Lists and search are unavailable; files can still be read.
    case failed(String)
  }
}

/// The reply of a command that has nothing to say beyond having succeeded.
public struct Done: Hashable, Codable, Sendable {
  public init() {}
}
