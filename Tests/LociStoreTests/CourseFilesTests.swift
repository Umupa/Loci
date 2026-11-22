import Foundation
import LociModel
import Testing

@testable import LociStore

struct CourseFilesTests {
  @Test("A course can reopen its metadata, finished Markdown, highlighted text and read progress")
  func coursesReopenFromFiles() throws {
    try withStore { store in
      var course = try writingCourse()
      let first = try #require(course.lessons.first)
      let second = try #require(course.lessons.last)
      try store.createCourse(course)
      try store.writeLesson("Any two majorities intersect.", in: course.id, lesson: first.id)
      try course.markLessonRead(first.id)
      try store.editCourse(course.id) { $0 = course }
      let content = ContentRef.lesson(course: course.id, lesson: first.id)
      let note = try Note(
        id: Fixture.id(8), locator: Locator(TextQuote("majorities"), in: content), savedAt: Fixture.instant)
      try store.append(.saved(note), on: content)

      let reopened = Store(root: store.root, discard: .permanently)
      #expect(try reopened.course(course.id) == course)
      #expect(try reopened.lessonText(in: course.id, lesson: first.id) == "Any two majorities intersect.")
      #expect(try reopened.lessonText(in: course.id, lesson: second.id) == nil)
      #expect(
        try reopened.coursePage(course.id).lessons == [
          CourseLesson(lesson: first, body: .written, isRead: true),
          CourseLesson(lesson: second, body: .unwritten, isRead: false),
        ])
      #expect(reopened.notes(on: content).value == [note])
    }
  }

  @Test("A broken course or lesson is reported by path while other courses stay available")
  func badCourseFiles() throws {
    try withStore { store in
      let course = try writingCourse()
      let other = try Course(id: Fixture.id(9), topic: "Paxos", createdAt: Fixture.instant)
      let lesson = try #require(course.lessons.first)
      try store.createCourse(course)
      try store.createCourse(other)
      try store.write(Data([0xFF]), to: store.lessonFile(in: course.id, lesson: lesson.id))

      guard case .invalid(let problem) = try store.coursePage(course.id).lessons.first?.body else {
        Issue.record("The broken lesson should show a file problem")
        return
      }
      #expect(problem.path == "courses/\(course.id)/lessons/\(lesson.id).md")
      #expect(problem.subject == .course(course.id))
      try store.writeLesson("Corrected.", in: course.id, lesson: lesson.id)
      #expect(try store.coursePage(course.id).lessons.first?.body == .written)
      try store.writeFile("courses/\(other.id)/course.json", "{ broken")
      #expect(store.courseIDs() == [course.id, other.id].sorted())
      #expect(throws: StoreError.self) { try store.course(other.id) }
      #expect(try store.course(course.id) == course)
    }
  }

  @Test("The course mirror rebuilds the same directory and lesson status after external edits")
  func mirrorsCourseFiles() throws {
    try withStore { store in
      let database = try StoreDatabase.inMemory()
      let course = try writingCourse()
      let lesson = try #require(course.lessons.first)
      try store.createCourse(course)
      try database.rebuild(from: store)
      #expect(try database.coursePages().first?.lessons.first?.body == .unwritten)
      try store.writeFile("courses/\(course.id)/lessons/\(lesson.id).md", "Written in Finder")

      #expect(try database.apply([.course(course.id)], from: store).isEmpty)
      let incremental = try database.coursePages()
      #expect(incremental.first?.lessons.first?.body == .written)
      try database.rebuild(from: store)
      #expect(try database.coursePages() == incremental)
    }
  }

  @Test("Finder changes to course files invalidate the course and changes to highlights invalidate the lesson")
  func seesCoursePaths() throws {
    let course = try writingCourse()
    let lesson = try #require(course.lessons.first)
    var map = ChangeMap(folders: [:])
    #expect(
      map.changes(at: ["courses/\(course.id)/lessons/\(lesson.id).md"], identify: { _ in nil }) == [.course(course.id)])
    #expect(
      map.changes(at: ["courses/\(course.id)/notes/\(lesson.id).jsonl"], identify: { _ in nil }) == [
        .notes(.lesson(course: course.id, lesson: lesson.id))
      ])
    #expect(map.changes(at: ["courses"], identify: { _ in nil }) == [.everything])
  }

  @Test("Restoring a deleted course brings back its lessons and their highlights")
  func courseUndo() throws {
    try withStore { store in
      let course = try writingCourse()
      let lesson = try #require(course.lessons.first)
      let content = ContentRef.lesson(course: course.id, lesson: lesson.id)
      try store.createCourse(course)
      try store.writeLesson("A lesson.", in: course.id, lesson: lesson.id)
      let note = try Note(
        id: Fixture.id(7), locator: Locator(TextQuote("lesson"), in: content), savedAt: Fixture.instant)
      try store.append(.saved(note), on: content)

      try store.setAsideCourse(course.id)
      #expect(store.courseIDs().isEmpty)
      #expect(store.notes(on: content).value.isEmpty)
      try store.restoreCourse(course.id)
      #expect(try store.lessonText(in: course.id, lesson: lesson.id) == "A lesson.")
      #expect(store.notes(on: content).value == [note])
    }
  }

  @Test("A symbolic link in a course content path is reported as belonging to the course")
  func reportsLinkedCourseContent() throws {
    try withStore { store in
      let course = try writingCourse()
      let lesson = try #require(course.lessons.first)
      let directory = store.courseFolder(course.id).appending(path: "lessons")
      let fixture = store.root.appending(path: "fixture")
      try store.createCourse(course)
      try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
      try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: fixture)

      let page = try store.coursePage(course.id)
      guard case .invalid(let problem) = page.lessons.first?.body else {
        Issue.record("The lesson directory was accepted as part of the course")
        return
      }
      #expect(problem.subject == .course(course.id))
      #expect(throws: StoreError.self) { try store.lessonText(in: course.id, lesson: lesson.id) }
      #expect(throws: StoreError.self) { try store.writeLesson("Draft.", in: course.id, lesson: lesson.id) }
      #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.path()).isEmpty)
    }
  }

  @Test("A course's atlas is saved beside it, comes back with the course, and may point only at planned lessons")
  func savesAtlas() throws {
    try withStore { store in
      let course = try writingCourse()
      try store.createCourse(course)
      #expect(try store.coursePage(course.id).atlas == nil)
      let atlas = try sampleAtlas(pointingAt: "majorities")
      try store.writeCourseAtlas(atlas, in: course.id)
      let reopened = Store(root: store.root, discard: .permanently)
      #expect(try reopened.courseAtlas(course.id) == atlas)
      #expect(try reopened.coursePage(course.id).atlas == atlas)
      #expect(throws: StoreError.self) {
        try store.writeCourseAtlas(try sampleAtlas(pointingAt: "paxos"), in: course.id)
      }
      #expect(try store.courseAtlas(course.id) == atlas)
    }
  }

  private func sampleAtlas(pointingAt lesson: String) throws -> CourseAtlas {
    let json = """
      {"gist": "Any two majorities intersect.", "blocks": [{"kind": "cards", "title": "Safety",
       "cards": [{"title": "Quorum", "points": ["Two majorities share a node"], "lessons": ["\(lesson)"]}]}]}
      """
    return try JSONDecoder().decode(CourseAtlas.self, from: Data(json.utf8))
  }

  private func writingCourse() throws -> Course {
    var course = try Course(id: Fixture.id(1), topic: "Raft", createdAt: Fixture.instant)
    let option = try CourseQuestion.Option(title: "Yes", detail: "Proceed with this goal")
    let revise = try CourseQuestion.Option(title: "Revise", detail: "Change the goal")
    let draft = try CourseQuestion.Draft(
      question: "Ready?", options: [option, revise], multiple: false,
      purpose: .confirmation)
    try course.ask(CourseQuestion(id: Fixture.id(2), draft: draft))
    _ = try course.answer(question: Fixture.id(2), with: .option(0))
    try course.updateGoal(CourseGoal(subtitle: "Keep consensus", length: "Two lessons"))
    try course.markGoalReady()
    try course.beginSources()
    let url = try #require(URL(string: "https://example.org/paper.pdf"))
    _ = try course.addSource(CourseSource.Draft(url: url), id: Fixture.id(3))
    try course.beginWriting()
    let first = try Lesson(id: #require(Lesson.ID("majorities")), title: "Any two majorities intersect")
    let second = try Lesson(id: #require(Lesson.ID("terms")), title: "Terms decide who can lead")
    try course.replacePlan([first, second], keepingWritten: [])
    return course
  }
}
