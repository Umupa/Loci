import Foundation
import Testing

@testable import LociModel

struct CourseTests {
  @Test("A new course shows the topic and starts with an empty goal interview")
  func startsWithTopic() throws {
    let course = try makeCourse()
    #expect(course.title == "Raft")
    #expect(course.goal.title == "Raft")
    #expect(course.stage == .goal)
    #expect(course.goalStatus == .interview)
    #expect(course.lessons.isEmpty)
  }

  @Test("A follow-up takes two to four options and a confirmation has exactly two single choices")
  func validQuestions() throws {
    let option = try CourseQuestion.Option(title: "For work", detail: "Understand a decision")
    for count in 1...5 {
      let draft = try? CourseQuestion.Draft(
        question: "Why?", options: Array(repeating: option, count: count), multiple: false)
      #expect((draft != nil) == (2...4).contains(count))
    }
    #expect(throws: ModelError.self) {
      try CourseQuestion.Draft(question: "Right?", options: [option, option], multiple: true, purpose: .confirmation)
    }
    let malformed = Data(
      #"{"question":"Why?","options":[{"title":"Work","detail":"A decision"}],"multiple":false}"#.utf8)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(CourseQuestion.Draft.self, from: malformed)
    }
  }

  @Test("Only the current question accepts a valid answer in its offered mode")
  func answersCurrentQuestion() throws {
    var course = try makeCourse()
    let draft = try question(multiple: true, purpose: .followUp(field: .known))
    let id = EntityID()
    try course.ask(CourseQuestion(id: id, draft: draft))
    #expect(throws: ModelError.self) { try course.answer(question: EntityID(), with: .options([0])) }
    #expect(throws: ModelError.self) { try course.answer(question: id, with: .option(0)) }
    #expect(throws: ModelError.self) { try course.answer(question: id, with: .options([4])) }
    #expect(throws: ModelError.self) { try course.answer(question: id, with: .text("  ")) }
    #expect(
      try course.answer(question: id, with: .options([1, 0]))
        == .answered(question: draft.question, answers: ["Work", "Interview"]))
    #expect(course.question == nil)
    let revised = EntityID()
    try course.ask(CourseQuestion(id: revised, draft: try question()))
    #expect(
      try course.answer(question: revised, with: .text("  Curiosity "))
        == .answered(question: draft.question, answers: ["Curiosity"]))
    let single = EntityID()
    try course.ask(CourseQuestion(id: single, draft: try question()))
    #expect(
      try course.answer(question: single, with: .option(1))
        == .answered(question: draft.question, answers: ["Interview"]))
  }

  @Test("Only a confirmed goal with a subtitle and length can start gathering sources")
  func confirmsGoal() throws {
    var course = try makeCourse()
    try course.updateGoal(CourseGoal(purpose: "Understand quorum"))
    try course.updateGoal(CourseGoal(title: "Raft consensus", depth: "Internals"))
    #expect(course.goal.purpose == "Understand quorum")
    #expect(course.title == "Raft consensus")
    #expect(throws: ModelError.self) { try course.beginSources() }
    #expect(throws: ModelError.self) { try course.markGoalReady() }
    let draft = try question(purpose: .confirmation)
    let first = EntityID()
    try course.ask(CourseQuestion(id: first, draft: draft))
    #expect(course.goalStatus == .awaitingConfirmation)
    #expect(try course.answer(question: first, with: .option(1)) == .askedToReviseGoal)
    #expect(course.goalStatus == .interview)
    let second = EntityID()
    try course.ask(CourseQuestion(id: second, draft: draft))
    #expect(try course.answer(question: second, with: .option(0)) == .confirmedGoal)
    #expect(throws: ModelError.self) { try course.markGoalReady() }
    try course.updateGoal(CourseGoal(subtitle: "Why a quorum holds", length: "Five lessons"))
    try course.markGoalReady()
    try course.beginSources()
    #expect(course.stage == .sources)
    #expect(course.goalStatus == .ready)
    #expect(throws: ModelError.self) { try course.beginWriting() }
  }

  @Test("A pasted repository link keeps its card when pinned and a new commit needs to be read again")
  func pinsSources() throws {
    var course = try atSources()
    let url = try #require(URL(string: "https://github.com/example/repo"))
    let id = EntityID()
    let pasted = try course.addSource(CourseSource.Draft(url: url), id: id)
    #expect(pasted.kind == .page)
    #expect(throws: ModelError.self) { try CourseSource.Draft(url: url, kind: .repository) }
    let commit = try #require(CommitID(String(repeating: "a", count: 40)))
    let pinned = try course.addSource(CourseSource.Draft(url: url, title: "Code", commit: commit), id: EntityID())
    #expect(pinned.id == id)
    #expect(pinned.site == "github.com")
    #expect(pinned.commit == commit)
    try course.markSourceRead(id)
    #expect(course.sources.first?.isRead == true)
    let changed = try #require(CommitID(String(repeating: "b", count: 40)))
    let newVersion = try course.addSource(CourseSource.Draft(url: url, commit: changed), id: EntityID())
    #expect(!newVersion.isRead)
    #expect(newVersion.title == "Code")
    #expect(try course.removeSource(id) == newVersion)
    #expect(course.sources.isEmpty)
  }

  @Test("Changing the plan can move unfinished lessons and keeps written titles and their order")
  func protectsWrittenLessons() throws {
    var course = try atSources()
    let url = try #require(URL(string: "https://example.org/paper.pdf"))
    _ = try course.addSource(CourseSource.Draft(url: url), id: EntityID())
    try course.beginWriting()
    let first = try lesson("majority", "A majority intersects every other majority")
    let second = try lesson("terms", "Terms break ties")
    let third = try lesson("failure", "Partitions expose the trade-off")
    try course.replacePlan([first, second, third], keepingWritten: [])
    try course.markLessonRead(first.id)
    #expect(throws: ModelError.self) { try course.replacePlan([second, third], keepingWritten: [first.id]) }
    #expect(throws: ModelError.self) {
      try course.replacePlan([third, first, second], keepingWritten: [first.id, third.id])
    }
    let retitled = try Lesson(id: first.id, title: "A different claim")
    #expect(throws: ModelError.self) { try course.replacePlan([retitled, third], keepingWritten: [first.id]) }
    #expect(throws: ModelError.self) { try course.replacePlan([first, first], keepingWritten: []) }
    try course.replacePlan([second, first, third], keepingWritten: [first.id, third.id])
    #expect(course.lessons == [second, first, third])
    #expect(course.readLessons == [first.id])
    #expect(try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(course)) == course)
  }

  @Test("Lesson IDs are safe file names and notes keep their course and lesson in a link")
  func courseLocators() throws {
    for unsafe in ["", "..", "a/b", "a.md", "a%2fb", "UPPER", "-ending", "end-"] {
      #expect(Lesson.ID(unsafe) == nil)
    }
    let course = try makeCourse()
    let id = try #require(Lesson.ID("topic-1"))
    let quote = try TextQuote("Any two majorities intersect")
    let locator = Locator(quote, in: .lesson(course: course.id, lesson: id))
    #expect(Locator(locator.description) == locator)
    #expect(locator.content == .lesson(course: course.id, lesson: id))
    #expect(locator.quote == quote)
  }

  @Test("Only the course's changes refresh its metadata, Markdown and conversation feeds")
  func followsCourse() throws {
    let course = try makeCourse()
    let id = try #require(Lesson.ID("topic-1"))
    #expect(WatchCourse(course.id).isAffected(by: [.course(course.id)]))
    #expect(WatchCourse(course.id).isAffected(by: [.courseActivity(course.id)]))
    #expect(!WatchCourse(course.id).isAffected(by: [.course(EntityID())]))
    #expect(WatchLesson(course: course.id, lesson: id).isAffected(by: [.course(course.id)]))
    #expect(!WatchLesson(course: course.id, lesson: id).isAffected(by: [.courseActivity(course.id)]))
    #expect(OneConversation(.course(course.id)).isAffected(by: [.course(course.id)]))
    #expect(!OneConversation(.main).isAffected(by: [.course(course.id)]))
  }

  @Test("Course session tags and tool access tags identify the same course")
  func courseTags() throws {
    let course = try makeCourse()
    let ref = ConversationRef.course(course.id)
    let tool = LocalSession.course(course.id, access: EntityID())
    #expect(ConversationRef(tag: ref.tag) == ref)
    #expect(LocalSession(tag: tool.tag) == tool)
    #expect(tool.conversation == ref)
    #expect(LocalSession(tag: ref.tag) != tool)
  }

  private func makeCourse() throws -> Course {
    try Course(id: EntityID(), topic: "  Raft ", createdAt: Timestamp(millisecondsSince1970: 4))
  }

  private func question(
    multiple: Bool = false, purpose: CourseQuestion.Purpose = .followUp(field: nil)
  ) throws -> CourseQuestion.Draft {
    try CourseQuestion.Draft(
      question: "Why?",
      options: [
        CourseQuestion.Option(title: "Work", detail: "Use it in a system"),
        CourseQuestion.Option(title: "Interview", detail: "Explain it aloud"),
      ], multiple: multiple, purpose: purpose)
  }

  private func atSources() throws -> Course {
    var course = try makeCourse()
    let id = EntityID()
    try course.ask(CourseQuestion(id: id, draft: try question(purpose: .confirmation)))
    _ = try course.answer(question: id, with: .option(0))
    try course.updateGoal(CourseGoal(subtitle: "A quorum holds", length: "Five lessons"))
    try course.markGoalReady()
    try course.beginSources()
    return course
  }

  private func lesson(_ id: String, _ title: String) throws -> Lesson {
    try Lesson(id: #require(Lesson.ID(id)), title: title)
  }
}
