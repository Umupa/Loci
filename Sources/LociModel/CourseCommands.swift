import Foundation

public struct ListCourses: RemoteCommand {
  public static let name = "courses.list"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> [CourseEntry] {
    try await handler.listCourses()
  }
}

public struct StartCourse: RemoteCommand {
  public static let name = "course.start"
  public let topic: String

  public init(topic: String) {
    self.topic = topic
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Course {
    try await handler.startCourse(self)
  }
}

public struct AnswerCourseQuestion: RemoteCommand {
  public static let name = "course.answer"
  public let course: EntityID
  public let question: EntityID
  public let answer: CourseAnswer

  public init(course: EntityID, question: EntityID, answer: CourseAnswer) {
    self.course = course
    self.question = question
    self.answer = answer
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.answerCourseQuestion(self)
  }
}

public struct BeginCourseSources: RemoteCommand {
  public static let name = "course.beginSources"
  public let course: EntityID

  public init(_ course: EntityID) {
    self.course = course
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.beginCourseSources(self)
  }
}

public struct AddCourseSource: RemoteCommand {
  public static let name = "course.addSource"
  public let course: EntityID
  public let url: URL

  public init(course: EntityID, url: URL) {
    self.course = course
    self.url = url
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> CourseSource {
    try await handler.addCourseSource(self)
  }
}

public struct RemoveCourseSource: RemoteCommand {
  public static let name = "course.removeSource"
  public let course: EntityID
  public let source: EntityID

  public init(course: EntityID, source: EntityID) {
    self.course = course
    self.source = source
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.removeCourseSource(self)
  }
}

public struct BeginCourseWriting: RemoteCommand {
  public static let name = "course.beginWriting"
  public let course: EntityID

  public init(_ course: EntityID) {
    self.course = course
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.beginCourseWriting(self)
  }
}

public struct ReadLesson: RemoteCommand {
  public static let name = "course.readLesson"
  public let course: EntityID
  public let lesson: Lesson.ID

  public init(course: EntityID, lesson: Lesson.ID) {
    self.course = course
    self.lesson = lesson
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> String? {
    try await handler.readLesson(course, lesson: lesson)
  }
}

public struct OpenLesson: RemoteCommand {
  public static let name = "course.openLesson"
  public let course: EntityID
  public let lesson: Lesson.ID

  public init(course: EntityID, lesson: Lesson.ID) {
    self.course = course
    self.lesson = lesson
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.openLesson(self)
  }
}

public struct WriteLessonNow: RemoteCommand {
  public static let name = "course.writeLessonNow"
  public let course: EntityID
  public let lesson: Lesson.ID

  public init(course: EntityID, lesson: Lesson.ID) {
    self.course = course
    self.lesson = lesson
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.writeLessonNow(self)
  }
}

public struct DeleteCourse: RemoteCommand {
  public static let name = "course.delete"
  public let course: EntityID

  public init(_ course: EntityID) {
    self.course = course
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.deleteCourse(self)
  }
}

public struct RestoreDeletedCourse: RemoteCommand {
  public static let name = "course.restoreDeleted"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> Course? {
    try await handler.restoreDeletedCourse()
  }
}
