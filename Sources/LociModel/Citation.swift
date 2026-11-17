/// One lesson of one mentor.
public struct LessonRef: Hashable, Codable, Sendable {
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

extension Citation: Codable {
  private enum CodingKeys: String, CodingKey {
    case lesson, item, anchor
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let lesson = try container.decode(LessonRef.self, forKey: .lesson)
    let item = try container.decode(EntityID.self, forKey: .item)
    let locator = try container.decodeIfPresent(Locator.self, forKey: .anchor)
    switch locator {
    case nil:
      self.init(lesson: lesson, item: item, anchor: nil)
    case .item(item, let anchor):
      self.init(lesson: lesson, item: item, anchor: anchor)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .anchor, in: container, debugDescription: "the anchor points outside item \(item)")
    }
  }

  /// The anchor is written as a full locator into the item, so it reads the same as one in a lesson.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(lesson, forKey: .lesson)
    try container.encode(item, forKey: .item)
    try container.encodeIfPresent(anchor.map { Locator.item(item, $0) }, forKey: .anchor)
  }
}
