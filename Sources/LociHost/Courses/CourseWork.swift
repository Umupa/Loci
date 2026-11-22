import LociModel

struct CourseWork {
  enum Request {
    case event(CourseEvent)
    case message(Prompt, saying: String, lesson: Lesson.ID?)

    var lesson: Lesson.ID? {
      switch self {
      case .event(.writeLesson(let lesson, _)): lesson
      case .message(_, _, let lesson): lesson
      case .event: nil
      }
    }

    var isInitialLesson: Bool {
      if case .event(.writeLesson(_, .firstLessons)) = self { true } else { false }
    }
  }

  struct Action {
    let request: Request
    let recorded: EntityID?
  }

  struct Active {
    let id: EntityID
    let action: Action
    var request: Request { action.request }
  }

  private(set) var pending: [Action] = []
  var active: Active?

  var isWorking: Bool { active != nil || !pending.isEmpty }

  mutating func enqueue(_ request: Request, recorded: EntityID? = nil) {
    if let recorded, active?.action.recorded == recorded || pending.contains(where: { $0.recorded == recorded }) {
      return
    }
    let action = Action(request: request, recorded: recorded)
    switch request {
    case .event(.writeLesson(let lesson, let reason)):
      if reason == .requested {
        pending.removeAll { $0.request.lesson == lesson }
        if active?.request.lesson != lesson || recorded != nil { pending.insert(action, at: 0) }
      } else if active?.request.lesson != lesson && !pending.contains(where: { $0.request.lesson == lesson }) {
        pending.append(action)
      }
    default:
      pending.append(action)
    }
  }

  mutating func clearInitialLessons() {
    pending.removeAll { $0.request.isInitialLesson }
  }

  mutating func start(_ id: EntityID) -> Active? {
    guard !pending.isEmpty else { return nil }
    let next = Active(id: id, action: pending.removeFirst())
    active = next
    return next
  }

  mutating func complete(_ active: Active, failedInitialLesson: Bool) {
    self.active = nil
    if active.request.isInitialLesson, failedInitialLesson { clearInitialLessons() }
  }
}
