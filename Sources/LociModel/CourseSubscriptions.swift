/// The course gallery, including courses whose files need attention.
public struct WatchCourses: Subscription {
  public static let name = "courses"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> [CourseEntry] {
    try await handler.listCourses()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .course, .courseActivity, .everything: true
      default: false
      }
    }
  }
}

/// One course's goal, sources, table of contents and current work.
public struct WatchCourse: Subscription {
  public static let name = "course"
  public let course: EntityID

  public init(_ course: EntityID) {
    self.course = course
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> CoursePage {
    try await handler.coursePage(course)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.course(course)) || changes.contains(.courseActivity(course)) || changes.contains(.everything)
  }
}

/// The Markdown of a lesson, including changes to an already written lesson.
public struct WatchLesson: Subscription {
  public static let name = "course.lesson"
  public let course: EntityID
  public let lesson: Lesson.ID

  public init(course: EntityID, lesson: Lesson.ID) {
    self.course = course
    self.lesson = lesson
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> String? {
    try await handler.readLesson(course, lesson: lesson)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.course(course)) || changes.contains(.everything)
  }
}
