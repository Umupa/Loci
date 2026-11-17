import LociModel

/// How a piece of content is named in the database: the same path a locator uses,
/// `library/<id>` or `mentor/<id>/lesson/<slug>`.
enum ContentKey {
  static func key(_ content: ContentRef) -> String {
    switch content {
    case .item(let item): "library/\(item)"
    case .lesson(let lesson): "mentor/\(lesson.mentor)/lesson/\(lesson.lesson)"
    }
  }

  static func content(_ key: String) -> ContentRef? {
    let parts = key.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    switch parts.count {
    case 2 where parts[0] == "library":
      return EntityID(canonical: parts[1]).map(ContentRef.item)
    case 4 where parts[0] == "mentor" && parts[2] == "lesson":
      guard let mentor = EntityID(canonical: parts[1]), let slug = Lesson.Slug(parts[3]) else { return nil }
      return .lesson(LessonRef(mentor: mentor, lesson: slug))
    default:
      return nil
    }
  }

  static func mentor(_ id: EntityID) -> String { "mentor/\(id)" }
  static func notes(_ content: ContentRef) -> String { "notes/\(key(content))" }
}
