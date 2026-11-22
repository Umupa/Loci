import LociModel

extension CoursePage {
  var initialLessonsToWrite: [Lesson.ID] {
    Array(lessons.prefix(3)).filter { $0.body == .unwritten }.map(\.id)
  }

  var lastWrittenLesson: CourseLesson? { lessons.last { $0.body == .written } }

  var nextLessonAfterLastWritten: Lesson.ID? {
    guard let last = lessons.lastIndex(where: { $0.body == .written }), lessons.indices.contains(last + 1),
      lessons[last + 1].body == .unwritten
    else { return nil }
    return lessons[last + 1].id
  }
}

extension CourseEvent {
  var completesWhenTurnSettles: Bool {
    switch self {
    case .beganSources, .addedSource, .removedSource: true
    case .started, .answered, .confirmedGoal, .askedToReviseGoal, .beganWriting, .writeLesson: false
    }
  }

  func isSatisfied(by page: CoursePage) -> Bool {
    switch self {
    case .started, .answered, .askedToReviseGoal:
      page.course.question != nil || page.course.stage != .goal || page.course.goalStatus == .ready
    case .confirmedGoal: page.course.goalStatus == .ready
    case .beganWriting: !page.lessons.isEmpty
    case .writeLesson(let lesson, _): !page.lessons.contains { $0.id == lesson && $0.body != .written }
    case .beganSources: page.course.stage != .sources
    case .addedSource, .removedSource: false
    }
  }
}
