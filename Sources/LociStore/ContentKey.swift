import LociModel

/// How a piece of content is named in the database: the same path a locator uses, `library/<id>`.
enum ContentKey {
  static func key(_ content: ContentRef) -> String {
    switch content {
    case .item(let item): "library/\(item)"
    }
  }

  static func content(_ key: String) -> ContentRef? {
    let parts = key.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2, parts[0] == "library" else { return nil }
    return EntityID(canonical: parts[1]).map(ContentRef.item)
  }

  static func notes(_ content: ContentRef) -> String { "notes/\(key(content))" }
}
