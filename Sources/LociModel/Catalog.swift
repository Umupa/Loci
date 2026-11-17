import Foundation

/// A mentor's chapters and lessons, in reading order; the contents of `catalog.yaml`.
public struct Catalog: Hashable, Sendable {
  public let chapters: [Chapter]

  public init(chapters: [Chapter]) throws {
    let slugs = chapters.flatMap { $0.lessons.map(\.slug) }
    var seen = Set<Lesson.Slug>()
    for slug in slugs where !seen.insert(slug).inserted {
      throw ModelError("lesson \(slug) appears twice in the catalog")
    }
    self.chapters = chapters
  }

  /// A titled group of lessons. Nothing points at a chapter, so it has no identifier.
  public struct Chapter: Hashable, Sendable {
    public let title: String
    public let lessons: [Lesson]

    public init(title: String, lessons: [Lesson]) throws {
      self.title = try title.requiringText("chapter title")
      self.lessons = lessons
    }
  }
}

extension Catalog: Codable {
  private enum CodingKeys: String, CodingKey {
    case chapters
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
    self = try decoder.validated { try Catalog(chapters: chapters) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(chapters, forKey: .chapters)
  }
}

extension Catalog.Chapter: Codable {
  private enum CodingKeys: String, CodingKey {
    case title, lessons
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let title = try container.decode(String.self, forKey: .title)
    let lessons = try container.decodeIfPresent([Lesson].self, forKey: .lessons) ?? []
    self = try decoder.validated { try Catalog.Chapter(title: title, lessons: lessons) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encode(lessons, forKey: .lessons)
  }
}
