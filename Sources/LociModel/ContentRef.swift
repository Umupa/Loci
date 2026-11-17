/// One piece of content a reader can open: an item in the library, or a mentor's lesson.
public enum ContentRef: Hashable, Sendable {
  case item(EntityID)
  case lesson(LessonRef)
}

extension Locator {
  /// The content this locator points into.
  public var content: ContentRef {
    switch self {
    case .item(let item, _): .item(item)
    case .lesson(let lesson, _): .lesson(lesson)
    }
  }
}
