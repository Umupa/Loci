import LociModel

extension FakeHost {
  func listCourses() async throws(HostError) -> [CourseEntry] { (courses?.summaries ?? []).map(CourseEntry.course) }

  func coursePage(_ course: EntityID) async throws(HostError) -> CoursePage {
    guard let courses, course == courses.raft.id else { throw .notFound(course.description) }
    return courses.page
  }

  func startCourse(_ command: StartCourse) async throws(HostError) -> Course {
    guard let courses else { throw .notFound(command.topic) }
    return courses.raft
  }

  func answerCourseQuestion(_ command: AnswerCourseQuestion) async throws(HostError) -> Done { Done() }
  func beginCourseSources(_ command: BeginCourseSources) async throws(HostError) -> Done { Done() }

  func addCourseSource(_ command: AddCourseSource) async throws(HostError) -> CourseSource {
    throw .notFound(command.course.description)
  }

  func removeCourseSource(_ command: RemoveCourseSource) async throws(HostError) -> Done { Done() }
  func beginCourseWriting(_ command: BeginCourseWriting) async throws(HostError) -> Done { Done() }

  func readLesson(_ course: EntityID, lesson: Lesson.ID) async throws(HostError) -> String? {
    guard let courses, course == courses.raft.id else { throw .notFound(course.description) }
    return courses.lesson(lesson)
  }

  func openLesson(_ command: OpenLesson) async throws(HostError) -> Done { Done() }
  func writeLessonNow(_ command: WriteLessonNow) async throws(HostError) -> Done { Done() }
  func deleteCourse(_ command: DeleteCourse) async throws(HostError) -> Done { Done() }
  func restoreDeletedCourse() async throws(HostError) -> Course? { nil }
}
