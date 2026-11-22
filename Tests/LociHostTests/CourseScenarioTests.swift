import Foundation
import LociAgents
import LociModel
import LociStore
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct CourseScenarioTests {
  @Test("The course asks about the initial topic and goes to sources only after the reader confirms")
  func buildsTheGoal() async throws {
    try await withCourseHost { host, _, agent in
      let course = try await host.run(StartCourse(topic: "Raft quorum"))
      let session = try await turn(for: course.id, on: agent)
      let access = try await tag(for: course.id, on: agent)
      #expect(await session.prompts.last?.contains("Raft quorum") == true)
      #expect(await session.prompts.last?.contains("# Writing a course") == true)
      #expect(try await host.coursePage(course.id).activity == .working)
      await #expect(throws: HostError.self) { try await host.run(BeginCourseSources(course.id)) }
      let draft = try question()
      try await run(.ask(draft), in: access, on: host)
      let page = try await host.coursePage(course.id)
      let ask = try #require(page.course.question)
      await session.finish()
      try await idle(course.id, on: host)
      _ = try await host.run(AnswerCourseQuestion(course: course.id, question: ask.id, answer: .option(0)))
      _ = try await turn(for: course.id, on: agent, number: 2)
      #expect(await session.prompts.last?.contains(draft.options[0].title) == true)
      try await run(.ask(question(confirmation: true)), in: access, on: host)
      let confirmation = try #require(try await host.coursePage(course.id).course.question)
      await session.finish()
      try await idle(course.id, on: host)
      _ = try await host.run(AnswerCourseQuestion(course: course.id, question: confirmation.id, answer: .option(0)))
      _ = try await turn(for: course.id, on: agent, number: 3)
      try await run(
        .goal(CourseGoal(subtitle: "What keeps the leader unique", length: "Five lessons")),
        in: access, on: host)
      try await run(.ready, in: access, on: host)
      await session.finish()
      try await idle(course.id, on: host)
      #expect(try await host.coursePage(course.id).canBeginSources)
      _ = try await host.run(BeginCourseSources(course.id))
      _ = try await turn(for: course.id, on: agent, number: 4)
      #expect(try await host.coursePage(course.id).course.stage == .sources)
      #expect(try await host.run(ListItems()).isEmpty)
      #expect(try await host.conversation(.main).entries.isEmpty)
      await session.finish()
    }
  }

  @Test("Only an active course session can use its tools and one course cannot change another")
  func toolsAreBoundToTheConversation() async throws {
    try await withCourseHost { host, _, agent in
      let first = try await host.run(StartCourse(topic: "First"))
      let second = try await host.run(StartCourse(topic: "Second"))
      let firstSession = try await turn(for: first.id, on: agent)
      _ = try await turn(for: second.id, on: agent)
      let access = try await tag(for: first.id, on: agent)
      let draft = try question()
      let rejectedSessions: [LocalSession?] = [
        nil, .conversation(.main), .conversation(.course(first.id)), .panelRefresh(first.id),
      ]
      for outside in rejectedSessions {
        guard case .failed = await answer(.ask(draft), from: outside, on: host) else {
          Issue.record("Course tools accepted a tag outside a live course")
          continue
        }
      }
      guard case .course(_, let key) = access else { throw HostError.notFound("course tool tag") }
      guard case .failed = await answer(.ask(draft), from: .course(second.id, access: key), on: host) else {
        Issue.record("The tool key worked for a different course")
        return
      }
      try await run(.ask(draft), in: access, on: host)
      #expect(try await host.coursePage(first.id).course.question?.draft == draft)
      #expect(try await host.coursePage(second.id).course.question == nil)
      await firstSession.finish()
      try await idle(first.id, on: host)
      guard case .failed = await answer(.ask(draft), from: access, on: host) else {
        Issue.record("A settled turn could still write to its course")
        return
      }
    }
  }

  @Test("Starting to write plans the full course and produces the first three lessons in order")
  func draftsThreeLessons() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .sources, in: place, id: EntityID())
      _ = try await host.run(BeginCourseWriting(course.id))
      let session = try await turn(for: course.id, on: agent)
      let access = try await tag(for: course.id, on: agent)
      let plan = try lessons()
      try await run(.plan(plan), in: access, on: host)
      await session.finish()
      for (number, lesson) in plan.prefix(3).enumerated() {
        _ = try await turn(for: course.id, on: agent, number: number + 2)
        guard case .writing(let id, _) = try await host.coursePage(course.id).activity else {
          Issue.record("The course did not show its active lesson")
          return
        }
        #expect(id == lesson.id)
        try await run(.writeLesson(lesson.id, markdown: "A lesson about \(lesson.title)."), in: access, on: host)
        await session.finish()
      }
      try await idle(course.id, on: host)
      let page = try await host.coursePage(course.id)
      #expect(page.firstReadableLesson == plan[0].id)
      #expect(page.lessons.map(\.body) == [.written, .written, .written, .unwritten, .unwritten])
      #expect(try await host.run(ListItems()).isEmpty)
    }
  }

  @Test("Reading the last written lesson queues one successor and now-write takes the next turn")
  func opensAndWrites() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .writing, in: place, id: EntityID())
      let plan = course.lessons
      try place.store.writeLesson("First text.", in: course.id, lesson: plan[0].id)
      _ = try await host.run(OpenLesson(course: course.id, lesson: plan[0].id))
      let session = try await turn(for: course.id, on: agent)
      let access = try await tag(for: course.id, on: agent)
      let updated = Array(plan.dropFirst())
      guard case .failed(.invalidRequest) = await answer(.plan(updated), from: access, on: host) else {
        Issue.record("The new plan removed a lesson written to disk")
        return
      }
      _ = try await host.run(OpenLesson(course: course.id, lesson: plan[0].id))
      _ = try await host.run(OpenLesson(course: course.id, lesson: plan[3].id))
      _ = try await host.run(WriteLessonNow(course: course.id, lesson: plan[3].id))
      #expect(try await host.coursePage(course.id).course.readLessons == [plan[0].id])
      try await run(.writeLesson(plan[1].id, markdown: "Second text."), in: access, on: host)
      await session.finish()
      _ = try await turn(for: course.id, on: agent, number: 2)
      let pending = try await host.conversation(.course(course.id)).turn?.messages.first
      guard case .prompt(let prompt) = pending?.body else {
        Issue.record("The writing request did not start a course turn")
        return
      }
      #expect(prompt.lessonTitle == plan[3].title)
      #expect(
        await session.prompts.last?.contains(
          "The person asked to write lesson \(plan[3].id) now. Write that lesson in this turn.") == true)
      #expect(try await host.coursePage(course.id).activity == .writing(lesson: plan[3].id, draft: nil))
      try await run(.writeLesson(plan[3].id, markdown: "Fourth text."), in: access, on: host)
      await session.finish()
      try await idle(course.id, on: host)
      #expect(await session.prompts.count == 2)
    }
  }

  @Test("A question about a highlighted lesson allows Loci to revise it and the reading feed updates")
  func revisesALesson() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .writing, in: place, id: EntityID())
      let lesson = course.lessons[0]
      try place.store.writeLesson("First text.", in: course.id, lesson: lesson.id)
      let content = ContentRef.lesson(course: course.id, lesson: lesson.id)
      let passage = try Passage(locator: Locator(TextQuote("First text."), in: content), excerpt: "First text.")
      _ = try await host.run(
        SendMessage(
          to: .course(course.id), text: "Can you work a case?", passage: passage,
          lesson: lesson.id))
      let session = try await turn(for: course.id, on: agent)
      let access = try await tag(for: course.id, on: agent)
      #expect(await session.prompts.last?.contains(lesson.title) == true)
      try await run(.writeLesson(lesson.id, markdown: "Second text."), in: access, on: host)
      await session.emit(.text(" Added a worked case."))
      await session.finish()
      try await idle(course.id, on: host)
      let feed = host.subscribe(WatchLesson(course: course.id, lesson: lesson.id))
      #expect(await value(feed) { $0 == "Second text." } == "Second text.")
      #expect(try await host.notes(on: content).first?.exchanges.count == 1)
    }
  }

  @Test("Deleting a course closes its conversation and undo restores its messages and lessons")
  func deletionAndUndo() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .writing, in: place, id: EntityID())
      let lesson = course.lessons[0]
      try place.store.writeLesson("First text.", in: course.id, lesson: lesson.id)
      _ = try await host.run(SendMessage(to: .course(course.id), text: "Explain it", lesson: lesson.id))
      _ = try await turn(for: course.id, on: agent)
      _ = try await host.run(DeleteCourse(course.id))
      #expect(try await host.run(ListCourses()).isEmpty)
      await #expect(throws: HostError.self) { try await host.conversation(.course(course.id)) }
      #expect(try await host.run(RestoreDeletedCourse())?.id == course.id)
      #expect(try await host.conversation(.course(course.id)).entries.count >= 2)
      #expect(try await host.run(ReadLesson(course: course.id, lesson: lesson.id)) == "First text.")
    }
  }

  @Test("A course keeps links and read badges in its sources phase and tells Loci about user edits")
  func gathersSources() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .sources, in: place, id: EntityID())
      let url = try #require(URL(string: "https://github.com/example/raft"))
      let pasted = try await host.run(AddCourseSource(course: course.id, url: url))
      let session = try await turn(for: course.id, on: agent)
      let access = try await tag(for: course.id, on: agent)
      #expect(await session.prompts.last?.contains(url.absoluteString) == true)
      let sha = try #require(CommitID(String(repeating: "b", count: 40)))
      try await run(
        .addSource(CourseSource.Draft(url: url, title: "Raft code", kind: .repository, commit: sha)),
        in: access, on: host)
      try await run(.readSource(pasted.id), in: access, on: host)
      guard case .value(let bytes) = await answer(.listSources, from: access, on: host) else {
        Issue.record("The course did not list its sources")
        return
      }
      let sources = try JSONDecoder().decode([CourseSource].self, from: bytes)
      #expect(sources.last?.id == pasted.id)
      #expect(sources.last?.commit == sha && sources.last?.isRead == true)
      #expect(!((try await host.coursePage(course.id)).canBeginWriting))
      _ = try await host.run(RemoveCourseSource(course: course.id, source: pasted.id))
      await session.finish()
      _ = try await turn(for: course.id, on: agent, number: 2)
      #expect(await session.prompts.last?.contains("removed this source") == true)
      await session.finish()
      try await idle(course.id, on: host)
      #expect(try await host.coursePage(course.id).canBeginWriting)
      #expect(try await host.run(ListItems()).isEmpty)
    }
  }

  @Test("An active course publishes its draft and enables reading only after the Markdown is saved")
  func showsDraftProgress() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .writing, in: place, id: EntityID())
      let lesson = course.lessons[0]
      let progress = host.subscribe(WatchCourse(course.id))
      _ = try await host.run(WriteLessonNow(course: course.id, lesson: lesson.id))
      let session = try await turn(for: course.id, on: agent)
      let prompt = try #require(await session.prompts.last)
      let match = try #require(prompt.firstMatch(of: #/workspace/courses/[a-f0-9-]+/[a-f0-9-]+/[a-z0-9-]+\.md/#))
      let url = place.store.agentFolder.appending(path: String(match.0))
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let paragraph = "One completed paragraph.\n\n"
      try Data(paragraph.utf8).write(to: url, options: .atomic)
      let draft = await value(progress, within: .seconds(5)) {
        $0.activity == .writing(lesson: lesson.id, draft: paragraph)
      }
      #expect(draft != nil)
      #expect(draft?.firstReadableLesson == nil)
      let access = try await tag(for: course.id, on: agent)
      try await run(.writeLesson(lesson.id, markdown: "A finished lesson."), in: access, on: host)
      #expect(await value(progress, within: .seconds(5)) { $0.firstReadableLesson == lesson.id } != nil)
      await session.finish()
      try await idle(course.id, on: host)
      #expect(!FileManager.default.fileExists(atPath: url.path()))
    }
  }

  @Test("A paired Mac can continue writing a course and read the last saved text while offline")
  func courseWorksOnAPairedMac() async throws {
    let agent = FakeAgent(provider: .codex) { _ in .hang }
    try await TwoMacs.with(agent: agent) { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let course = try seed(stage: .writing, in: macs.studio.place, id: EntityID())
      let first = course.lessons[0]
      let second = course.lessons[1]
      try macs.studio.place.store.writeLesson("First text.", in: course.id, lesson: first.id)
      #expect(
        await value(remote.subscribe(WatchCourses()), within: .seconds(5)) {
          $0.map(\.id) == [course.id]
        } != nil)
      #expect(try await remote.run(ListCourses()).map(\.id) == [course.id])
      let progress = remote.subscribe(WatchCourse(course.id))
      let reading = remote.subscribe(WatchLesson(course: course.id, lesson: second.id))
      _ = try await remote.run(OpenLesson(course: course.id, lesson: first.id))
      let live = await value(remote.subscribe(OneConversation(.course(course.id))), within: .seconds(5)) {
        $0.turn?.messages.contains { if case .reply("Working") = $0.body { true } else { false } } == true
      }
      #expect(live != nil)
      let access = try #require(
        agent.opened.last?.environment[LocalCall.sessionVariable].flatMap(LocalSession.init(tag:)))
      try await run(.writeLesson(second.id, markdown: "Second text."), in: access, on: macs.studio.local)
      #expect(await value(reading, within: .seconds(5)) { $0 == "Second text." } == "Second text.")
      #expect(
        await value(progress, within: .seconds(5)) {
          $0.course.readLessons == [first.id] && $0.lessons[1].body == .written
        } != nil)
      let command = ReadLesson(course: course.id, lesson: second.id)
      #expect(try await remote.run(command) == "Second text.")
      await macs.studio.service.stop()
      #expect(await macs.connected(macs.laptop, to: macs.studio, link: .offline))
      #expect(try await remote.run(command) == "Second text.")
      await #expect(throws: HostError.offline) {
        try await remote.run(WriteLessonNow(course: course.id, lesson: second.id))
      }
    }
  }

  @Test("Reopening the app restores the course's lessons, reading state and conversation")
  func courseSurvivesRestart() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .writing, in: place, id: EntityID())
      for first in course.lessons.prefix(3) {
        try place.store.writeLesson("An initial lesson.", in: course.id, lesson: first.id)
      }
      let lesson = try #require(course.lessons.last)
      try place.store.writeLesson("The last lesson.", in: course.id, lesson: lesson.id)
      _ = try await host.run(OpenLesson(course: course.id, lesson: lesson.id))
      _ = try await host.run(SendMessage(to: .course(course.id), text: "Keep this for later", lesson: lesson.id))
      let session = try await turn(for: course.id, on: agent)
      await session.finish()
      try await idle(course.id, on: host)
      let conversation = try await host.conversation(.course(course.id))
      await host.close()

      let reopened = try await LocalHost.start(
        root: place.root, database: place.database,
        environment: TestWorld(agent: FakeAgent(provider: .codex)).environment)
      #expect(try await reopened.coursePage(course.id).course.readLessons == [lesson.id])
      #expect(try await reopened.readLesson(course.id, lesson: lesson.id) == "The last lesson.")
      #expect(try await reopened.conversation(.course(course.id)).entries == conversation.entries)
      await reopened.close()
    }
  }

}
