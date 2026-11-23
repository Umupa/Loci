import Foundation
import LociModel

@testable import LociUI

/// The design's courses as a host serves them: Raft, with its goal settled, six sources, three lessons written,
/// the first read and the fourth being written; and the other books of the gallery.
struct SampleCourses {
  let raft: Course
  let page: CoursePage
  let summaries: [CourseSummary]
  let conversation: Conversation?

  init(conversation: Conversation? = nil) throws {
    self.conversation = conversation
    var course = try Course(
      id: BuilderSamples.raft, topic: "Raft", createdAt: Timestamp(millisecondsSince1970: 1_763_300_000_000))
    let confirmation = try BuilderSamples.restated()
    try course.ask(confirmation)
    _ = try course.answer(question: confirmation.id, with: .option(0))
    try course.updateGoal(try BuilderSamples.goal(5, subtitle: true))
    try course.markGoalReady()
    try course.beginSources()
    for (index, address) in ReadingSamples.addresses.enumerated() {
      guard let url = URL(string: address) else { continue }
      let source = try course.addSource(
        CourseSource.Draft(url: url, title: BuilderSamples.sources[index].title), id: BuilderSamples.sourceIDs[index])
      if index < 4 { try course.markSourceRead(source.id) }
    }
    try course.beginWriting()
    let lessons = try zip(BuilderSamples.lessonIDs, BuilderSamples.titles).map { try Lesson(id: $0, title: $1) }
    try course.replacePlan(lessons, keepingWritten: [])
    try course.markLessonRead(lessons[0].id)
    raft = course
    page = CoursePage(
      course: course,
      lessons: lessons.enumerated().map { index, lesson in
        CourseLesson(lesson: lesson, body: index < 3 ? .written : .unwritten, isRead: index == 0)
      },
      activity: .writing(lesson: lessons[3].id, draft: nil))
    summaries =
      [
        CourseSummary(
          id: course.id, title: "Raft", subtitle: "一群机器怎么对一串日志达成一致", stage: .writing, lessonCount: 10,
          writtenCount: 3, readCount: 1, isWorking: true)
      ]
      + CourseSamples.books.dropFirst().map { book in
        CourseSummary(
          id: book.id, title: book.title, subtitle: book.subtitle, stage: .writing, lessonCount: 10,
          writtenCount: 10, readCount: Int(book.read * 10), isWorking: false)
      }
  }

  func lesson(_ lesson: Lesson.ID) -> String? {
    BuilderSamples.lessonIDs.prefix(3).contains(lesson) ? ReadingSamples.markdown : nil
  }

  /// The highlight left on the first lesson.
  func notes(on lesson: Lesson.ID) throws -> [Note] {
    guard lesson == BuilderSamples.lessonIDs[0] else { return [] }
    return [
      try Note(
        id: EntityID(),
        locator: .lesson(course: raft.id, lesson: lesson, quote: try TextQuote(ReadingSamples.highlighted)),
        excerpt: ReadingSamples.highlighted, savedAt: Timestamp(millisecondsSince1970: 1_763_340_000_000))
    ]
  }
}
