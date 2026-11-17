import LociModel
import Testing

@testable import LociUI

/// UI-S2: choosing a course opens its current lesson, and its lessons show how far the reader is.
struct CourseTests {
  static func page(_ sample: Sample, written: [String], read: [String]) throws -> MentorPage {
    let base = try #require(sample.pages[sample.scheduling.id])
    return MentorPage(
      mentor: base.mentor, catalog: base.catalog, writtenLessons: written.compactMap(Lesson.Slug.init),
      readLessons: Set(read.compactMap(Lesson.Slug.init)))
  }

  static func ref(_ sample: Sample, _ slug: String) throws -> Place {
    .lesson(LessonRef(mentor: sample.scheduling.id, lesson: try #require(Lesson.Slug(slug))))
  }

  @Test func aCourseOpensAtTheFirstWrittenLessonNotYetRead() throws {
    let sample = try Sample()
    let page = try Self.page(
      sample, written: ["why-a-scheduler", "filter-and-score", "borg"], read: ["why-a-scheduler"])

    #expect(Course(page: page).destination == (try Self.ref(sample, "filter-and-score")))
  }

  @Test func aCourseReadToTheEndOpensAtItsLastWrittenLesson() throws {
    let sample = try Sample()
    let page = try Self.page(
      sample, written: ["why-a-scheduler", "filter-and-score"], read: ["why-a-scheduler", "filter-and-score"])

    #expect(Course(page: page).destination == (try Self.ref(sample, "filter-and-score")))
  }

  @Test func aCourseWithNothingWrittenOpensItsMentor() throws {
    let sample = try Sample()

    #expect(Course(page: try Self.page(sample, written: [], read: [])).destination == .mentor(sample.scheduling.id))
    #expect(
      Course(page: try #require(sample.pages[sample.sandbox.id])).destination == .mentor(sample.sandbox.id))
  }

  @Test func eachLessonShowsReadCurrentUnreadOrUnwritten() throws {
    let sample = try Sample()
    let page = try Self.page(
      sample, written: ["why-a-scheduler", "filter-and-score", "borg"], read: ["why-a-scheduler"])

    #expect(Course(page: page).lessons.map(\.state) == [.read, .current, .unread, .unwritten])
  }

  @Test func theLessonOnScreenIsTheCurrentOne() throws {
    let sample = try Sample()
    let page = try Self.page(
      sample, written: ["why-a-scheduler", "filter-and-score", "borg"], read: ["why-a-scheduler"])

    #expect(
      Course(page: page, open: Lesson.Slug("why-a-scheduler")).lessons.map(\.state)
        == [.current, .unread, .unread, .unwritten])
  }

  @Test func aCourseIsCalledWhatThePersonAskedToLearn() throws {
    let sample = try Sample()
    let asked = try Mentor(
      id: sample.scheduling.id, name: "调度", avatar: sample.scheduling.avatar, color: sample.scheduling.color,
      provider: .pi, request: "想学 Kubernetes 调度")
    let page = MentorPage(mentor: asked, catalog: nil, writtenLessons: [])

    #expect(Course(page: page).title == "想学 Kubernetes 调度")
    #expect(Course(page: try #require(sample.pages[sample.sandbox.id])).title == "沙箱")
  }
}
