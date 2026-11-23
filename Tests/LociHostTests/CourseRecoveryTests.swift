import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

extension CourseScenarioTests {
  @Test("Reopening a course saved in the writing stage with an empty directory asks for the plan")
  func recoversAnUnplannedCourse() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .sources, in: place, id: EntityID())
      _ = try await host.run(BeginCourseWriting(course.id))
      _ = try await turn(for: course.id, on: agent)
      await host.close()
      try await reopened(place) { resumed in
        #expect(await coursePrompt(on: resumed, course: course.id, event: .beganWriting) != nil)
      }
    }
  }

  @Test("Reopening schedules the missing initial lessons and the successor of the last lesson read")
  func recoversInitialAndContinuingWork() async throws {
    try await withCourseHost { host, place, _ in
      let initial = try seed(stage: .writing, in: place, id: EntityID())
      let continuing = try seed(stage: .writing, in: place, id: EntityID())
      try place.store.writeLesson("The first lesson.", in: initial.id, lesson: initial.lessons[0].id)
      for lesson in continuing.lessons.prefix(3) {
        try place.store.writeLesson("A lesson.", in: continuing.id, lesson: lesson.id)
      }
      var read = continuing
      try read.markLessonRead(continuing.lessons[2].id)
      try place.store.editCourse(read.id) { $0 = read }
      await host.close()

      try await reopened(place) { resumed in
        #expect(
          await coursePrompt(
            on: resumed, course: initial.id,
            event: .writeLesson(initial.lessons[1].id, reason: .firstLessons)) != nil)
        #expect(
          await coursePrompt(
            on: resumed, course: continuing.id,
            event: .writeLesson(continuing.lessons[3].id, reason: .openedLastWritten)) != nil)
        let first = try await resumed.run(ReadLesson(course: initial.id, lesson: initial.lessons[0].id))
        #expect(first == "The first lesson.")
      }
    }
  }

  @Test("An interrupted first question is asked after reopening")
  func recoversTheFirstQuestion() async throws {
    try await withCourseHost { host, place, agent in
      let course = try await host.run(StartCourse(topic: "Raft"))
      _ = try await turn(for: course.id, on: agent)
      await host.close()
      try await reopened(place) { resumed in
        #expect(await coursePrompt(on: resumed, course: course.id, event: .started(topic: "Raft")) != nil)
      }
    }
  }

  @Test("Reopening sends an accepted answer even if its turn never started")
  func replaysAnUnprocessedAnswer() async throws {
    try await withCourseHost { host, place, agent in
      let course = try await host.run(StartCourse(topic: "Raft"))
      _ = try await turn(for: course.id, on: agent)
      let access = try await tag(for: course.id, on: agent)
      let draft = try question()
      try await run(.ask(draft), in: access, on: host)
      let pending = try #require(try await host.coursePage(course.id).course.question)
      _ = try await host.run(AnswerCourseQuestion(course: course.id, question: pending.id, answer: .option(0)))
      await host.close()
      try await reopened(place) { resumed in
        #expect(
          await coursePrompt(
            on: resumed, course: course.id,
            event: .answered(question: draft.question, answers: [draft.options[0].title])) != nil)
      }
    }
  }

  @Test("An explicit stop survives reopening and the reader can restart the empty writing stage")
  func manualStopSurvivesRestart() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .sources, in: place, id: EntityID())
      _ = try await host.run(BeginCourseWriting(course.id))
      _ = try await turn(for: course.id, on: agent)
      _ = try await host.run(StopTurn(in: .course(course.id)))
      await host.close()
      try await reopened(place) { resumed in
        let paused = try await resumed.coursePage(course.id)
        #expect(paused.course.workPaused && paused.activity == .idle)
        _ = try await resumed.run(BeginCourseWriting(course.id))
        let prompt = await coursePrompt(on: resumed, course: course.id, event: .beganWriting)
        let health = await resumed.health()
        #expect(prompt != nil, "Host health: \(health.database)")
      }
    }
  }

  @Test("Recovery uses an answer already stored by a previous version", arguments: [false, true])
  func recoversALegacyAnswer(confirmation: Bool) async throws {
    let place = Place()
    defer { place.remove() }
    let date = TestWorld.instant
    var course = try Course(id: EntityID(), topic: "Raft", createdAt: date)
    let draft = try question(confirmation: confirmation)
    let ask = CourseQuestion(id: EntityID(), draft: draft)
    try course.ask(ask)
    let answer = try course.answer(question: ask.id, with: .option(0))
    try place.store.createCourse(course)
    let database = try StoreDatabase.open(at: place.database)
    let session = SessionRecord(
      id: EntityID(), owner: .conversation(.course(course.id)), runtime: Runtime(provider: .codex),
      instructions: "legacy", startedAt: date)
    try database.start(session)
    try database.append(
      [
        Message(id: EntityID(), at: date, body: .prompt(Prompt(text: "An answer", purpose: .course(answer)))),
        Message(id: EntityID(), at: date, body: .ended(.interrupted)),
      ], to: session.id)

    try await reopened(place) { resumed in
      #expect(await coursePrompt(on: resumed, course: course.id, event: answer) != nil)
    }
  }

  private func reopened(_ place: Place, _ body: (LocalHost) async throws -> Void) async throws {
    let world = TestWorld(agent: FakeAgent(provider: .codex) { _ in .hang }, idOffset: 1000)
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    do {
      try await body(host)
    } catch {
      await host.close()
      throw error
    }
    await host.close()
  }

  private func coursePrompt(on host: LocalHost, course: EntityID, event: CourseEvent) async -> Conversation? {
    await value(host.subscribe(OneConversation(.course(course)))) {
      $0.turn?.messages.contains {
        if case .prompt(let prompt) = $0.body { return prompt.purpose == .course(event) }
        return false
      } == true
    }
  }
}
