import LociModel

/// How a piece of content is named in the database: the same path a locator uses, `library/<id>`.
enum ContentKey {
  static func key(_ content: ContentRef) -> String {
    switch content {
    case .item(let item): "library/\(item)"
    case .lesson(let course, let lesson): "courses/\(course)/\(lesson)"
    }
  }

  static func content(_ key: String) -> ContentRef? {
    let parts = key.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if parts.count == 2, parts[0] == "library" { return EntityID(canonical: parts[1]).map(ContentRef.item) }
    if parts.count == 3, parts[0] == "courses", let course = EntityID(canonical: parts[1]),
      let lesson = Lesson.ID(parts[2])
    {
      return .lesson(course: course, lesson: lesson)
    }
    return nil
  }

  static func notes(_ content: ContentRef) -> String { "notes/\(key(content))" }
}
