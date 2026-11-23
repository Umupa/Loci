import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

extension CourseScenarioTests {
  @Test("A replacement plan determines all three initial writing targets and when the atlas is drawn")
  func replacementPlanWritesItsFirstThree() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .sources, in: place, id: EntityID())
      _ = try await host.run(BeginCourseWriting(course.id))
      let session = try await turn(for: course.id, on: agent)
      let access = try await tag(for: course.id, on: agent)
      let plan = try lessons()
      try await run(.plan(plan), in: access, on: host)
      try await run(.plan(Array(plan.dropFirst())), in: access, on: host)
      await session.finish()
      for (offset, lesson) in plan.dropFirst().prefix(3).enumerated() {
        if offset == 1 {
          _ = try await turn(for: course.id, on: agent, number: 3)
          try await run(.atlas(atlas(pointingAt: lesson.id)), in: access, on: host)
          await session.finish()
        }
        _ = try await turn(for: course.id, on: agent, number: offset == 0 ? 2 : offset + 3)
        #expect(try await host.coursePage(course.id).activity == .writing(lesson: lesson.id, draft: nil))
        try await run(.writeLesson(lesson.id, markdown: "Finished."), in: access, on: host)
        await session.finish()
      }
      try await idle(course.id, on: host)
    }
  }

  @Test("A source the reader removes stays out until the reader adds it again")
  func removedSourceStaysOut() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .sources, in: place, id: EntityID())
      let url = try #require(course.sources.first?.url)
      _ = try await host.run(SendMessage(to: .course(course.id), text: "Find more sources"))
      let session = try await turn(for: course.id, on: agent)
      let access = try await tag(for: course.id, on: agent)
      _ = try await host.run(RemoveCourseSource(course: course.id, source: course.sources[0].id))
      guard case .failed = await answer(.addSource(try CourseSource.Draft(url: url)), from: access, on: host) else {
        Issue.record("The unprocessed removal did not keep the source out")
        return
      }
      await session.finish()
      _ = try await turn(for: course.id, on: agent, number: 2)
      guard case .failed = await answer(.addSource(try CourseSource.Draft(url: url)), from: access, on: host) else {
        Issue.record("The removal did not survive into the next turn")
        return
      }
      _ = try await host.run(AddCourseSource(course: course.id, url: url))
      try await run(
        .addSource(CourseSource.Draft(url: url, title: "Reader's link", kind: .paper)), in: access, on: host)
      #expect(try await host.coursePage(course.id).course.sources.first?.title == "Reader's link")
      await session.finish()
    }
  }

  @Test("A new agent session gets its own course tool credentials")
  func credentialsFollowAgentSession() async throws {
    try await withCourseHost { host, _, agent in
      let course = try await host.run(StartCourse(topic: "Raft"))
      let first = try await turn(for: course.id, on: agent)
      let original = try await tag(for: course.id, on: agent)
      await first.finish()
      try await idle(course.id, on: host)
      _ = try await host.run(StartOver(in: .course(course.id)))
      _ = try await host.run(SendMessage(to: .course(course.id), text: "Ask me the first question"))
      for _ in 0..<200 {
        if let newest = await agent.sessions.last, await newest.prompts.count == 1, await agent.sessions.count == 2 {
          let current = try await tag(for: course.id, on: agent)
          #expect(current != original)
          try await run(.ask(question()), in: current, on: host)
          await newest.finish()
          return
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      Issue.record("A new course session did not start")
    }
  }

  @Test("A course update preserves external edits made after its earlier read")
  func retriesAnIncrementalUpdateAfterFinderChanges() async throws {
    try await withCourseHost { host, place, _ in
      let course = try seed(stage: .writing, in: place, id: EntityID())
      let lesson = try #require(course.lessons.first)
      var externallyEdited = false
      _ = try await host.courses.mutate(course.id) { value in
        if !externallyEdited {
          externallyEdited = true
          var latest = try place.store.course(course.id)
          _ = try latest.addSource(
            CourseSource.Draft(url: #require(URL(string: "https://example.com/editor"))), id: EntityID())
          try place.store.editCourse(latest.id) { $0 = latest }
        }
        try value.markLessonRead(lesson.id)
        return (Done(), nil)
      }
      #expect(try place.store.course(course.id).readLessons == [lesson.id])
      #expect(try place.store.course(course.id).sources.count == 2)
    }
  }

  @Test("A highlight arriving during course deletion is refused and undo restores the course")
  func noteCannotRecreateADeletingCourse() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let agent = ManualAgent(opensFreely: 0, provider: .codex)
    let environment = world.environment(running: { _ in agent }, runtime: Runtime(provider: .codex))
    let course = try seed(stage: .writing, in: place, id: EntityID())
    let first = course.lessons[0].id
    let second = course.lessons[1].id
    try place.store.writeLesson("A passage.", in: course.id, lesson: first)
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: environment)
    _ = try await host.run(WriteLessonNow(course: course.id, lesson: second))
    for _ in 0..<200 {
      if await agent.waitingToOpen != 0 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await agent.waitingToOpen == 1)
    let deletion = Task { try await host.run(DeleteCourse(course.id)) }
    for _ in 0..<200 {
      do {
        _ = try await host.run(OpenLesson(course: course.id, lesson: second))
      } catch HostError.notFound {
        break
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    let locator = try Locator(TextQuote("A passage."), in: .lesson(course: course.id, lesson: first))
    await #expect(throws: HostError.self) {
      try await host.run(AddNote(locator: locator, excerpt: "A passage."))
    }
    await agent.openFreely()
    _ = try await deletion.value
    #expect(try await host.run(RestoreDeletedCourse())?.id == course.id)
    await host.close()
  }

  @Test("An offline read cannot return a lesson the remote host already reported missing")
  func missingLessonInvalidatesRemoteRead() async throws {
    try await TwoMacs.with(agent: FakeAgent(provider: .codex)) { macs in
      try await macs.pair()
      let host = macs.laptop.service.open(macs.studio.machine.id)
      let course = try seed(stage: .writing, in: macs.studio.place, id: EntityID())
      let lesson = course.lessons[0].id
      try macs.studio.place.store.writeLesson("Saved before deletion.", in: course.id, lesson: lesson)
      let read = ReadLesson(course: course.id, lesson: lesson)
      #expect(try await host.run(read) == "Saved before deletion.")
      let reading = host.subscribe(WatchLesson(course: course.id, lesson: lesson))
      #expect(await value(reading) { $0 == "Saved before deletion." } != nil)
      _ = try await macs.studio.local.run(DeleteCourse(course.id))
      let missing = await first(reading) {
        if case .unavailable(.notFound) = $0 { true } else { false }
      }
      #expect(missing != nil)
      await macs.studio.service.stop()
      #expect(await macs.connected(macs.laptop, to: macs.studio, link: .offline))
      await #expect(throws: HostError.self) { try await host.run(read) }
    }
  }
}
