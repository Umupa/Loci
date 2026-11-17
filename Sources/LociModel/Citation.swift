/// One lesson of one mentor.
public struct LessonRef: Hashable, Sendable {
  public let mentor: EntityID
  public let lesson: Lesson.Slug

  public init(mentor: EntityID, lesson: Lesson.Slug) {
    self.mentor = mentor
    self.lesson = lesson
  }
}

/// A lesson citing an item: listed among its sources, or pointed at from its text.
public struct Citation: Hashable, Sendable {
  public let lesson: LessonRef
  public let item: EntityID
  /// Where in the item the lesson points; `nil` when the lesson cites the item as a whole.
  public let anchor: ItemAnchor?

  public init(lesson: LessonRef, item: EntityID, anchor: ItemAnchor?) {
    self.lesson = lesson
    self.item = item
    self.anchor = anchor
  }

  /// The citation a locator in the lesson's text makes. A locator into another lesson cites no item.
  public init?(in lesson: LessonRef, pointingAt locator: Locator) {
    guard case .item(let item, let anchor) = locator else { return nil }
    self.init(lesson: lesson, item: item, anchor: anchor)
  }
}
