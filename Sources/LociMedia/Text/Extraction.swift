import Foundation

/// What defuddle found on a page: its readable text as Markdown and what the page says about itself. Every
/// field is as the page gave it, so empty strings are common.
struct Extraction: Hashable, Decodable, Sendable {
  let title: String
  let author: String
  let site: String
  let published: String
  let language: String
  let domain: String
  let markdown: String

  init(
    title: String, author: String = "", site: String = "", published: String = "", language: String = "",
    domain: String = "", markdown: String
  ) {
    self.title = title
    self.author = author
    self.site = site
    self.published = published
    self.language = language
    self.domain = domain
    self.markdown = markdown
  }

  private enum CodingKeys: String, CodingKey {
    case title, author, site, published, language, domain, markdown
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func text(_ key: CodingKeys) throws -> String { try container.decodeIfPresent(String.self, forKey: key) ?? "" }
    self.init(
      title: try text(.title), author: try text(.author), site: try text(.site), published: try text(.published),
      language: try text(.language), domain: try text(.domain), markdown: try text(.markdown))
  }
}
