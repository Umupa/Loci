/// One lesson as its reader shows it: the text, what it cites, the mentor's glossary, and what comes next.
public struct LessonPage: Hashable, Codable, Sendable {
  public let lesson: LessonRef
  /// `nil` when the lesson is written but missing from its mentor's catalog.
  public let title: String?
  public let text: String
  public let citations: [Citation]
  public let glossary: Glossary
  /// The lesson after this one in the catalog, if there is one.
  public let next: Upcoming?

  public init(
    lesson: LessonRef, title: String?, text: String, citations: [Citation], glossary: Glossary, next: Upcoming?
  ) {
    self.lesson = lesson
    self.title = title
    self.text = text
    self.citations = citations
    self.glossary = glossary
    self.next = next
  }

  /// A lesson further on in the catalog, which the mentor may not have written yet.
  public struct Upcoming: Hashable, Codable, Sendable {
    public let lesson: Lesson
    public let written: Bool

    public init(lesson: Lesson, written: Bool) {
      self.lesson = lesson
      self.written = written
    }
  }
}

/// One lesson, kept current as the mentor revises it or its catalog.
public struct OneLesson: Subscription {
  public static let name = "lesson"
  public let lesson: LessonRef

  public init(lesson: LessonRef) {
    self.lesson = lesson
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> LessonPage {
    try await handler.lessonPage(lesson)
  }

  /// Any lesson of the mentor, because the next one may just have been written.
  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .lesson(let changed): changed.mentor == lesson.mentor
      case .mentor(let mentor), .catalog(let mentor): mentor == lesson.mentor
      case .everything: true
      case .item, .notes, .conversation, .answers, .reading: false
      }
    }
  }
}

/// Records that the reader has seen the lesson as it is now. Replies with the text they saw before when
/// the mentor has revised it since, so the reader can show what changed; otherwise `nil`.
public struct SeeLesson: Command {
  public static let name = "lesson.see"
  public let lesson: LessonRef

  public init(lesson: LessonRef) {
    self.lesson = lesson
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> String? {
    try await handler.seeLesson(lesson)
  }
}
