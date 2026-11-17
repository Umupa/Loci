import Testing

@testable import LociModel

struct CurrentLessonTests {
  private func page(written: [String], read: Set<String>) throws -> MentorPage {
    let lessons = try ["one", "two", "three"].map { try Lesson(slug: Lesson.Slug($0)!, title: $0) }
    let mentor = try Mentor(
      id: Fixture.mentor, name: "调度", avatar: "owl", color: MentorColor(red: 0, green: 0, blue: 0), provider: .pi)
    return MentorPage(
      mentor: mentor,
      catalog: try Catalog(chapters: [
        try Catalog.Chapter(title: "A", lessons: Array(lessons.prefix(2))),
        try Catalog.Chapter(title: "B", lessons: Array(lessons.suffix(1))),
      ]),
      writtenLessons: written.compactMap(Lesson.Slug.init), readLessons: Set(read.compactMap(Lesson.Slug.init)))
  }

  @Test func theCurrentLessonIsTheFirstWrittenOneNotYetRead() throws {
    #expect(try page(written: ["one", "two", "three"], read: ["one"]).currentLesson == Lesson.Slug("two"))
  }

  @Test func unwrittenLessonsAreSkipped() throws {
    #expect(try page(written: ["one", "three"], read: ["one"]).currentLesson == Lesson.Slug("three"))
  }

  @Test func withEverythingReadTheCurrentLessonIsTheLastWrittenOne() throws {
    #expect(try page(written: ["one", "two"], read: ["one", "two"]).currentLesson == Lesson.Slug("two"))
  }

  @Test func withNothingWrittenThereIsNoCurrentLesson() throws {
    #expect(try page(written: [], read: []).currentLesson == nil)
  }
}
