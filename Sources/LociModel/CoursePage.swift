public struct CourseSummary: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let title: String
  public let subtitle: String?
  public let stage: CourseStage
  public let lessonCount: Int
  public let writtenCount: Int
  public let readCount: Int
  public let isWorking: Bool

  public init(
    id: EntityID, title: String, subtitle: String?, stage: CourseStage, lessonCount: Int, writtenCount: Int,
    readCount: Int, isWorking: Bool
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.stage = stage
    self.lessonCount = lessonCount
    self.writtenCount = writtenCount
    self.readCount = readCount
    self.isWorking = isWorking
  }
}

public enum CourseEntry: Hashable, Codable, Sendable, Identifiable {
  case course(CourseSummary)
  case invalid(id: EntityID, problem: FileProblem)

  public var id: EntityID {
    switch self {
    case .course(let summary): summary.id
    case .invalid(let id, _): id
    }
  }
}

public struct CourseLesson: Hashable, Codable, Sendable, Identifiable {
  public enum Body: Hashable, Codable, Sendable {
    case unwritten, written
    case invalid(FileProblem)
  }

  public let lesson: Lesson
  public let body: Body
  public let isRead: Bool
  public var id: Lesson.ID { lesson.id }

  public init(lesson: Lesson, body: Body, isRead: Bool) {
    self.lesson = lesson
    self.body = body
    self.isRead = isRead
  }
}

public enum CourseActivity: Hashable, Codable, Sendable {
  case idle
  case working
  case writing(lesson: Lesson.ID, draft: String?)
}

public struct CoursePage: Hashable, Codable, Sendable {
  public let course: Course
  public let lessons: [CourseLesson]
  public let activity: CourseActivity

  public var canBeginSources: Bool {
    course.stage == .goal && course.goalStatus == .ready && activity == .idle
  }

  public var canBeginWriting: Bool {
    course.stage == .sources && !course.sources.isEmpty && activity == .idle
  }

  public var firstReadableLesson: Lesson.ID? {
    guard let first = lessons.first, first.body == .written else { return nil }
    return first.id
  }

  public init(course: Course, lessons: [CourseLesson], activity: CourseActivity = .idle) {
    self.course = course
    self.lessons = lessons
    self.activity = activity
  }
}
