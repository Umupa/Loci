import Foundation

/// One lesson in a mentor's catalog, whether or not it has been written yet.
///
/// The lesson's text lives in `lessons/<slug>.md`; its title lives only here.
public struct Lesson: Hashable, Sendable {
  public let slug: Slug
  public let title: String

  public init(slug: Slug, title: String) throws {
    self.slug = slug
    self.title = try title.requiringText("lesson title")
  }

  /// A lesson's identifier, chosen by the mentor that writes it: lowercase letters, digits and hyphens,
  /// not starting or ending with a hyphen. It is the lesson's file name and is unique within one mentor.
  public struct Slug: Hashable, Sendable, TextCodable {
    public let description: String

    public init?(_ description: String) {
      guard !description.hasPrefix("-"), !description.hasSuffix("-"),
        description.wholeMatch(of: /[a-z0-9-]+/) != nil
      else { return nil }
      self.description = description
    }
  }
}

extension Lesson: Codable {
  private enum CodingKeys: String, CodingKey {
    case slug, title
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let slug = try container.decode(Slug.self, forKey: .slug)
    let title = try container.decode(String.self, forKey: .title)
    self = try decoder.validated { try Lesson(slug: slug, title: title) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(slug, forKey: .slug)
    try container.encode(title, forKey: .title)
  }
}
