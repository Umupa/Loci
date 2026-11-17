import LociModel
import LociStore

extension LocalHost {
  /// Read from the files, which always win over the database; only the citations come from the mirror.
  public func lessonPage(_ lesson: LessonRef) async throws(HostError) -> LessonPage {
    let text = try attempt { try store.lesson(lesson).body }
    let lessons = (try? store.catalog(of: lesson.mentor))?.chapters.flatMap(\.lessons) ?? []
    let index = lessons.firstIndex { $0.slug == lesson.lesson }
    let next = index.flatMap { lessons.indices.contains($0 + 1) ? lessons[$0 + 1] : nil }
    return LessonPage(
      lesson: lesson, title: index.map { lessons[$0].title }, text: text,
      citations: try attempt { try database.citations(in: lesson) },
      glossary: (try? store.glossary(of: lesson.mentor)) ?? .empty,
      next: next.map { next in
        LessonPage.Upcoming(
          lesson: next, written: (try? store.lesson(LessonRef(mentor: lesson.mentor, lesson: next.slug))) != nil)
      })
  }

  public func seeLesson(_ lesson: LessonRef) async throws(HostError) -> String? {
    let before = try attempt { try database.see(try store.lesson(lesson).body, of: lesson) }
    await hub.refresh([.reading(.lesson(lesson))])
    return before
  }

  /// The mentor's lessons read to the end, and those revised since the reader last saw them.
  func readingMarks(of mentor: EntityID) -> (read: Set<Lesson.Slug>, revised: Set<Lesson.Slug>) {
    guard let record = try? database.readingRecord(of: mentor) else { return ([], []) }
    let revised = record.seen.compactMap { slug, seen in
      (try? store.lesson(LessonRef(mentor: mentor, lesson: slug)).body).flatMap { $0 == seen ? nil : slug }
    }
    return (record.read, Set(revised))
  }
}
