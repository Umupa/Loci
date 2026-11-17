/// The text of a written lesson, without its front matter.
public struct ReadLessonText: Command {
  public static let name = "lesson.text"
  public let lesson: LessonRef

  public init(lesson: LessonRef) {
    self.lesson = lesson
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> String {
    try await handler.lessonText(lesson)
  }
}

/// What one lesson cites, in the order it cites it.
public struct LessonCitations: Command {
  public static let name = "lesson.citations"
  public let lesson: LessonRef

  public init(lesson: LessonRef) {
    self.lesson = lesson
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [Citation] {
    try await handler.lessonCitations(lesson)
  }
}

/// Every lesson, of any mentor, that cites an item.
public struct ItemCitations: Command {
  public static let name = "item.citations"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [CitingLesson] {
    try await handler.citingLessons(of: item)
  }
}

public struct Search: Command {
  public static let name = "search"
  public let text: String
  public let limit: Int

  public init(text: String, limit: Int = 50) {
    self.text = text
    self.limit = limit
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [SearchHit] {
    try await handler.search(self)
  }
}

public struct ReadReadingState: Command {
  public static let name = "reading.read"
  public let content: ContentRef

  public init(content: ContentRef) {
    self.content = content
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> ReadingState? {
    try await handler.readingState(of: content)
  }
}

/// Remembers where the reader is. The position must point into the same content.
public struct SaveReadingState: Command {
  public static let name = "reading.save"
  public let content: ContentRef
  public let state: ReadingState

  public init(content: ContentRef, state: ReadingState) {
    self.content = content
    self.state = state
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.saveReadingState(self)
  }
}
