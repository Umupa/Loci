import Foundation
import LociModel
import LociStore

actor CourseKeeper {
  let context: AgentContext
  let loci: LociAgent
  private var works: [EntityID: CourseWork] = [:]
  private var tasks: [EntityID: Task<Void, Never>] = [:]
  private var deleting: Set<EntityID> = []
  private var stopping: Set<EntityID> = []
  private var closing = false

  init(context: AgentContext, loci: LociAgent) {
    self.context = context
    self.loci = loci
  }

  var store: Store { context.store }

  func list() async throws(HostError) -> [CourseEntry] {
    let health = await context.follower.hub.current()
    let pages = try attempt { try context.database.coursePages() }
    var entries: [(entry: CourseEntry, created: Date)] = pages.map { page in
      let course = page.course
      return (
        .course(
          CourseSummary(
            id: course.id, title: course.title, subtitle: course.goal.subtitle, stage: course.stage,
            lessonCount: page.lessons.count, writtenCount: page.lessons.count { $0.body == .written },
            readCount: page.lessons.count(where: \.isRead), isWorking: works[course.id]?.isWorking == true)),
        course.createdAt.date
      )
    }
    let shown = Set(entries.map { $0.entry.id })
    entries += health.fileProblems.compactMap { problem in
      guard problem.path.hasSuffix("/course.json"), case .course(let id) = problem.subject,
        !shown.contains(id)
      else { return nil }
      return (.invalid(id: id, problem: problem), id.createdAt)
    }
    return entries.sorted { ($0.created, $0.entry.id) > ($1.created, $1.entry.id) }.map(\.entry)
  }

  func page(_ id: EntityID) throws(HostError) -> CoursePage {
    let page = try attempt { try store.coursePage(id) }
    let activity: CourseActivity
    if let active = works[id]?.active, let lesson = active.request.lesson {
      activity = .writing(lesson: lesson, draft: store.courseDraft(id, turn: active.id, lesson: lesson))
    } else {
      activity = works[id]?.isWorking == true ? .working : .idle
    }
    return CoursePage(course: page.course, lessons: page.lessons, activity: activity, atlas: page.atlas)
  }

  func start(_ topic: String) async throws(HostError) -> Course {
    guard !closing else { throw .invalidRequest("the host is closing") }
    let (course, pending) = try attempt {
      var course = try Course(id: context.environment.newID(), topic: topic, createdAt: context.environment.now())
      let pending = course.keepEvent(.started(topic: course.title), id: context.environment.newID())
      try store.createCourse(course)
      return (course, pending)
    }
    enqueue(pending, for: course.id)
    await changed(course.id)
    return course
  }

  func mutate<Value: Sendable>(
    _ id: EntityID, requiresIdle: Bool = false, _ change: (inout Course) throws -> (Value, CourseEvent?)
  ) async throws(HostError) -> Value {
    try requireAvailable(id)
    if requiresIdle, works[id]?.isWorking == true { throw .invalidRequest(AgentRun.busy) }
    let (result, event) = try attempt {
      try store.editCourse(id) { course in
        let (result, event) = try change(&course)
        return (result, event.map { course.keepEvent($0, id: context.environment.newID()) })
      }
    }
    if let event { enqueue(event, for: id) }
    await changed(id)
    return result
  }

  func open(_ lesson: Lesson.ID, in id: EntityID) async throws(HostError) {
    try requireAvailable(id)
    let page = try attempt { try store.coursePage(id) }
    guard let opened = page.lessons.first(where: { $0.id == lesson }) else {
      throw .notFound(lesson.description)
    }
    guard opened.body == .written else { return }
    let atlas = try attempt {
      try store.editCourse(id) { course -> Course.PendingEvent? in
        let latest = try store.coursePage(id)
        guard latest.lessons.contains(where: { $0.id == lesson && $0.body == .written }) else {
          return nil
        }
        let firstRead = !course.readLessons.contains(lesson)
        try course.markLessonRead(lesson)
        guard firstRead, latest.atlas != nil else { return nil }
        return course.keepEvent(.drawAtlas(lesson), id: context.environment.newID())
      }
    }
    if let atlas { enqueue(atlas, for: id) }
    await changed(id)
  }

  func append(_ entry: NoteEntry, on content: ContentRef, course: EntityID) throws(HostError) {
    try requireAvailable(course)
    try attempt { try store.append(entry, on: content) }
  }

  func writeNow(_ lesson: Lesson.ID, in id: EntityID) async throws(HostError) {
    try requireAvailable(id)
    let page = try attempt { try store.coursePage(id) }
    guard let target = page.lessons.first(where: { $0.id == lesson }) else { throw .notFound(lesson.description) }
    guard target.body != .written else { return }
    let pending = try attempt {
      try store.editCourse(id) { course in
        course.keepEvent(.writeLesson(lesson, reason: .requested), id: context.environment.newID())
      }
    }
    enqueue(pending, for: id)
    await changed(id)
  }

  func say(_ prompt: Prompt, text: String, about lesson: Lesson.ID?, in id: EntityID) async throws(HostError) {
    try requireAvailable(id)
    guard works[id]?.isWorking != true else { throw .invalidRequest(AgentRun.busy) }
    try attempt {
      try store.editCourse(id) { course in
        if let lesson, !course.lessons.contains(where: { $0.id == lesson }) {
          throw HostError.notFound(lesson.description)
        }
        course.setWorkPaused(false)
      }
    }
    enqueue(.message(prompt, saying: text, lesson: lesson), for: id)
    await changed(id, files: false)
  }

  func run(_ request: CourseToolRequest, course id: EntityID, access: EntityID) async throws(HostError) -> Data {
    guard let active = works[id]?.active,
      let run = await loci.existingRun(of: .course(id)),
      await run.acceptsCourseTools(access),
      works[id]?.active?.id == active.id, !deleting.contains(id), !stopping.contains(id), !closing
    else { throw .invalidRequest(CourseToolRequest.scopeMessage) }

    let course = try attempt { try store.course(id) }
    switch request {
    case .listSources:
      return try WireCodec.encode(course.sources)
    case .writeLesson(let lesson, let markdown):
      switch active.request {
      case .event(.writeLesson(let target, _)) where lesson == target: break
      case .message: break
      default:
        throw .invalidRequest("write the lesson requested in this turn")
      }
      guard course.lessons.contains(where: { $0.id == lesson }) else {
        throw .invalidRequest("use a lesson ID from loci course plan")
      }
      guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw .invalidRequest("write some Markdown in the lesson file before saving")
      }
      try attempt {
        try store.writeLesson(markdown, in: id, lesson: lesson)
        if let recorded = active.action.recorded {
          try store.editCourse(id) { $0.completeEvent(recorded) }
        }
      }
      await changed(id)
      return try WireCodec.encode(Done())
    case .atlas(let atlas):
      switch active.request {
      case .event(.drawAtlas), .message: break
      default: throw .invalidRequest("draw the atlas when the app asks for it or the person does")
      }
      try attempt {
        do {
          try store.writeCourseAtlas(atlas, in: id)
        } catch StoreError.invalid(let problem) {
          throw HostError.invalidRequest(problem.reason)
        }
        if let recorded = active.action.recorded { try store.editCourse(id) { $0.completeEvent(recorded) } }
      }
      await changed(id)
      return try WireCodec.encode(Done())
    default:
      let reply = try apply(request, in: id, active: active)
      await changed(id)
      return reply
    }
  }

  private func apply(_ request: CourseToolRequest, in id: EntityID, active: CourseWork.Active)
    throws(HostError) -> Data
  {
    try attempt {
      var skeleton: Course.PendingEvent?
      let reply = try store.editCourse(id) { course in
        var reply = try WireCodec.encode(Done())
        switch request {
        case .ask(let draft):
          try course.ask(CourseQuestion(id: context.environment.newID(), draft: draft))
        case .goal(let changes):
          try course.updateGoal(changes)
        case .ready:
          try course.markGoalReady()
        case .addSource(let draft):
          reply = try WireCodec.encode(course.addSource(draft, id: context.environment.newID()))
        case .readSource(let id):
          try course.markSourceRead(id)
        case .plan(let lessons):
          let page = try store.coursePage(course.id)
          let recorded = Set(page.lessons.filter { $0.body != .unwritten }.map(\.id))
          try course.replacePlan(lessons, keepingWritten: recorded)
          if page.atlas == nil { skeleton = course.keepEvent(.drawAtlas(nil), id: context.environment.newID()) }
        case .listSources, .writeLesson, .atlas:
          throw HostError.invalidRequest("use the course tool in its matching turn")
        }
        if let recorded = active.action.recorded, case .event(let event) = active.request {
          switch (request, event) {
          case (.ask, .started), (.ask, .answered), (.ask, .askedToReviseGoal),
            (.ready, .confirmedGoal), (.plan, .beganWriting):
            course.completeEvent(recorded)
          default: break
          }
        }
        return reply
      }
      if case .plan = request {
        works[id]?.clearInitialLessons()
        let page = try store.coursePage(id)
        for (index, lesson) in page.initialLessonsToWrite.enumerated() {
          enqueue(.event(.writeLesson(lesson, reason: .firstLessons)), for: id)
          if index == 0, let skeleton { enqueue(skeleton, for: id) }
        }
        if page.initialLessonsToWrite.isEmpty, let skeleton { enqueue(skeleton, for: id) }
      }
      return reply
    }
  }

  func pause(_ id: EntityID) async throws(HostError) {
    try requireAvailable(id)
    try attempt { try store.editCourse(id) { $0.setWorkPaused(true) } }
    await stop(id)
    await changed(id)
  }

  func stop(_ id: EntityID) async {
    stopping.insert(id)
    let task = tasks[id]
    task?.cancel()
    await loci.existingRun(of: .course(id))?.stop()
    await task?.value
    stopping.remove(id)
  }

  func delete(_ id: EntityID) async throws(HostError) {
    try requireAvailable(id)
    deleting.insert(id)
    defer { deleting.remove(id) }
    await stop(id)
    await loci.forget(.course(id))
    do throws(HostError) {
      try attempt { try store.setAsideCourse(id) }
    } catch {
      await loci.forgotten(.course(id))
      throw error
    }
    await loci.forgotten(.course(id))
    await changed(id)
  }

  func restore() async throws(HostError) -> Course? {
    guard let id = store.setAsideCourses().first else { return nil }
    try attempt { try store.restoreCourse(id) }
    let course = try? store.course(id)
    recover(id)
    await changed(id)
    return course
  }

  func close() async {
    closing = true
    for id in Array(tasks.keys) { await stop(id) }
  }

  private func requireAvailable(_ id: EntityID) throws(HostError) {
    guard !deleting.contains(id) else { throw .notFound(id.description) }
    guard !closing, !stopping.contains(id) else { throw .invalidRequest("the course is stopping") }
  }

  func enqueue(_ event: Course.PendingEvent, for id: EntityID) {
    enqueue(.event(event.event), for: id, recorded: event.id)
  }

  func enqueue(_ request: CourseWork.Request, for id: EntityID, recorded: EntityID? = nil) {
    works[id, default: CourseWork()].enqueue(request, recorded: recorded)
    if tasks[id] == nil { tasks[id] = Task { await self.work(on: id) } }
  }

  private func work(on id: EntityID) async {
    while !Task.isCancelled, let active = works[id]?.start(context.environment.newID()) {
      await changed(id, files: false)
      guard !Task.isCancelled else { break }
      var settled = false
      do {
        let page = try store.coursePage(id)
        if let (prompt, text) = context.coursePrompt(active, in: page) {
          let run = try await loci.run(of: .course(id))
          if Task.isCancelled { break }
          try await run.send(prompt, saying: text)
          if Task.isCancelled { await run.stop() }
          let messages = await run.settle()
          settled = !messages.isEmpty && !messages.contains { if case .ended = $0.body { true } else { false } }
        }
        if !Task.isCancelled, let recorded = active.action.recorded, case .event(let event) = active.request {
          let latest = try store.coursePage(id)
          if event.isSatisfied(by: latest) || settled && event.completesWhenTurnSettles {
            try store.editCourse(id) { $0.completeEvent(recorded) }
            await changed(id)
          }
        }
      } catch StoreError.invalid, StoreError.notFound, HostError.invalidFile, HostError.notFound {
        await changed(id)
      } catch {
        await context.follower.hub.failed(String(describing: error))
      }
      let page = try? store.coursePage(id)
      let failed = page?.lessons.contains { $0.id == active.request.lesson && $0.body != .written } ?? false
      works[id]?.complete(active, failedInitialLesson: failed)
      try? store.removeCourseDrafts(id, turn: active.id)
    }
    if let active = works[id]?.active { try? store.removeCourseDrafts(id, turn: active.id) }
    works[id] = nil
    tasks[id] = nil
    await changed(id, files: false)
  }

  private func changed(_ id: EntityID, files: Bool = true) async {
    await context.follower.follow([files ? .course(id) : .courseActivity(id)])
  }
}
