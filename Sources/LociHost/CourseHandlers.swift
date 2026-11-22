import LociModel
import LociStore

extension LocalHost {
  public func listCourses() async throws(HostError) -> [CourseEntry] {
    try await courses.list()
  }

  public func coursePage(_ course: EntityID) async throws(HostError) -> CoursePage {
    try await courses.page(course)
  }

  public func startCourse(_ command: StartCourse) async throws(HostError) -> Course {
    try await courses.start(command.topic)
  }

  public func answerCourseQuestion(_ command: AnswerCourseQuestion) async throws(HostError) -> Done {
    try await courses.mutate(command.course) { course in
      (Done(), try course.answer(question: command.question, with: command.answer))
    }
  }

  public func beginCourseSources(_ command: BeginCourseSources) async throws(HostError) -> Done {
    try await courses.mutate(command.course, requiresIdle: true) { course in
      try course.beginSources()
      return (Done(), .beganSources)
    }
  }

  public func addCourseSource(_ command: AddCourseSource) async throws(HostError) -> CourseSource {
    try await courses.mutate(command.course) { course in
      if let existing = course.sources.first(where: { $0.url == command.url }) { return (existing, nil) }
      let source = try course.addSource(
        CourseSource.Draft(url: command.url), id: environment.newID(), chosenByReader: true)
      return (source, .addedSource(source))
    }
  }

  public func removeCourseSource(_ command: RemoveCourseSource) async throws(HostError) -> Done {
    try await courses.mutate(command.course) { course in
      (Done(), .removedSource(try course.removeSource(command.source)))
    }
  }

  public func beginCourseWriting(_ command: BeginCourseWriting) async throws(HostError) -> Done {
    try await courses.mutate(command.course, requiresIdle: true) { course in
      try course.beginWriting()
      return (Done(), .beganWriting)
    }
  }

  public func readLesson(_ course: EntityID, lesson: Lesson.ID) async throws(HostError) -> String? {
    try attempt { try store.lessonText(in: course, lesson: lesson) }
  }

  public func openLesson(_ command: OpenLesson) async throws(HostError) -> Done {
    try await courses.open(command.lesson, in: command.course)
    return Done()
  }

  public func writeLessonNow(_ command: WriteLessonNow) async throws(HostError) -> Done {
    try await courses.writeNow(command.lesson, in: command.course)
    return Done()
  }

  public func deleteCourse(_ command: DeleteCourse) async throws(HostError) -> Done {
    try await deletions.through { () async throws(HostError) in
      guard store.courseIDs().contains(command.course) else { throw .notFound(command.course.description) }
      let previous = setAsideDeletion()
      try await courses.delete(command.course)
      await discardSetAside(previous)
      return Done()
    }
  }

  public func restoreDeletedCourse() async throws(HostError) -> Course? {
    try await deletions.through { () async throws(HostError) in
      try await courses.restore()
    }
  }

  func discardSetAsideCourses(_ courses: [EntityID]) async {
    for id in courses {
      do {
        try store.expireCourseUndo(id)
      } catch {
        await hub.failed(String(describing: error))
      }
    }
    let stillUndoable = Set(store.setAsideCourses())
    for id in store.coursesAwaitingCleanup() where !stillUndoable.contains(id) {
      do {
        if try store.trashExpiredCourse(id) {
          try store.discardCourseConversation(id)
          try database.deleteConversation(.course(id))
        }
        try store.finishCourseCleanup(id)
      } catch {
        await hub.failed(String(describing: error))
      }
    }
  }
}
