import LociModel
import LociStore

extension CoursePage {
  var initialLessonsToWrite: [Lesson.ID] {
    Array(lessons.prefix(3)).filter { $0.body == .unwritten }.map(\.id)
  }
}

extension CourseEvent {
  var completesWhenTurnSettles: Bool {
    switch self {
    case .beganSources, .addedSource, .removedSource: true
    case .drawAtlas(let lesson): lesson != nil
    case .started, .answered, .confirmedGoal, .askedToReviseGoal, .beganWriting, .writeLesson: false
    }
  }

  func isSatisfied(by page: CoursePage) -> Bool {
    switch self {
    case .started, .answered, .askedToReviseGoal:
      page.course.question != nil || page.course.stage != .goal || page.course.goalStatus == .ready
    case .confirmedGoal: page.course.goalStatus == .ready
    case .beganWriting: !page.lessons.isEmpty
    case .writeLesson(_, .openedLastWritten): true
    case .writeLesson(let lesson, _): !page.lessons.contains { $0.id == lesson && $0.body != .written }
    case .beganSources: page.course.stage != .sources
    case .drawAtlas(nil): page.atlas != nil
    case .addedSource, .removedSource, .drawAtlas: false
    }
  }
}

extension CourseKeeper {
  func recoverWork() {
    for id in store.courseIDs() { recover(id) }
  }

  func recover(_ id: EntityID) {
    guard let page = try? store.coursePage(id), !page.course.workPaused else { return }
    let course = page.course
    for record in course.pendingEvents { enqueue(record, for: id) }
    switch course.stage {
    case .goal where course.pendingEvents.isEmpty && course.question == nil:
      if let event = legacyGoalWork(course) { enqueue(.event(event), for: id) }
    case .writing where course.lessons.isEmpty:
      if !course.pendingEvents.contains(where: { $0.event == .beganWriting }) {
        enqueue(.event(.beganWriting), for: id)
      }
    case .writing:
      for lesson in page.initialLessonsToWrite { enqueue(.event(.writeLesson(lesson, reason: .firstLessons)), for: id) }
    case .goal, .sources: break
    }
  }

  private func legacyGoalWork(_ course: Course) -> CourseEvent? {
    if course.goalStatus == .confirmed { return .confirmedGoal }
    guard course.goalStatus == .interview else { return nil }
    let messages = (try? context.database.messages(of: .conversation(.course(course.id)))) ?? []
    for message in messages.reversed() {
      guard case .prompt(let prompt) = message.body, case .course(let event) = prompt.purpose else { continue }
      switch event {
      case .started, .answered, .askedToReviseGoal: return event
      default: continue
      }
    }
    return .started(topic: course.title)
  }
}
