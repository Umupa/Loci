import Foundation
import LociModel
import Testing

@testable import LociHost
@testable import LociStore

struct LessonScenarioTests {
  /// A mentor with two lessons in one chapter, the first of them written.
  static func mentorWithLessons(_ host: LocalHost, _ place: Place) async throws -> (LessonRef, LessonRef) {
    let mentor = try await host.run(CreateMentor(request: "调度"))
    let first = LessonRef(mentor: mentor.id, lesson: try #require(Lesson.Slug("filter")))
    let second = LessonRef(mentor: mentor.id, lesson: try #require(Lesson.Slug("score")))
    try place.store.save(
      Catalog(chapters: [
        .init(
          title: "调度",
          lessons: [try Lesson(slug: first.lesson, title: "过滤"), try Lesson(slug: second.lesson, title: "打分")])
      ]), of: mentor.id)
    try place.store.save(LessonText(front: try Lesson.Front(sources: []), body: "# 过滤\n\n先排除不合适的节点。\n"), as: first)
    try place.store.save(
      Glossary(terms: [.init(term: "节点", definition: "一台能跑任务的机器。", lesson: second.lesson)]), of: mentor.id)
    await host.follow([.catalog(mentor.id), .lesson(first)])
    return (first, second)
  }

  @Test func aLessonComesWithItsTitleGlossaryAndTheLessonAfterIt() async throws {
    try await withHost { host, place, _ in
      let (first, second) = try await Self.mentorWithLessons(host, place)

      let page = try #require(await value(host.subscribe(OneLesson(lesson: first))) { _ in true })

      #expect(page.title == "过滤")
      #expect(page.text == "# 过滤\n\n先排除不合适的节点。\n")
      #expect(page.glossary.terms.map(\.term) == ["节点"])
      #expect(page.next == LessonPage.Upcoming(lesson: try Lesson(slug: second.lesson, title: "打分"), written: false))
    }
  }

  /// α2-S9: a lesson the mentor revised shows what the reader saw before, and the mentor page marks it.
  @Test func aRevisedLessonShowsWhatChangedSinceTheReaderSawIt() async throws {
    try await withHost { host, place, _ in
      let (first, _) = try await Self.mentorWithLessons(host, place)
      let page = host.subscribe(OneMentor(mentor: first.mentor))
      #expect(try await host.run(SeeLesson(lesson: first)) == nil)
      #expect(try await host.run(SeeLesson(lesson: first)) == nil)

      try place.store.save(
        LessonText(front: try Lesson.Front(sources: []), body: "# 过滤\n\n先排除资源不够的节点。\n"), as: first)
      await host.follow([.lesson(first)])

      let marked = await value(page) { $0.revisedLessons == [first.lesson] }
      #expect(marked != nil)
      #expect(try await host.run(SeeLesson(lesson: first)) == "# 过滤\n\n先排除不合适的节点。\n")
      let cleared = await value(page) { $0.revisedLessons.isEmpty }
      #expect(cleared != nil)
    }
  }

  /// α2-S3: reading a lesson to its end marks it read on the mentor page.
  @Test func readingToTheEndMarksTheLessonOnTheMentorPage() async throws {
    try await withHost { host, place, _ in
      let (first, _) = try await Self.mentorWithLessons(host, place)
      let page = host.subscribe(OneMentor(mentor: first.mentor))
      let unread = await value(page) { $0.readLessons.isEmpty && $0.catalog?.chapters.isEmpty == false }
      #expect(unread != nil)

      _ = try await host.run(MarkRead(content: .lesson(first)))

      let read = await value(page) { $0.readLessons == [first.lesson] }
      #expect(read != nil)
    }
  }

  @Test func aLessonFollowsItsFileAsTheMentorRewritesIt() async throws {
    try await withHost { host, place, _ in
      let (first, _) = try await Self.mentorWithLessons(host, place)
      let lesson = host.subscribe(OneLesson(lesson: first))
      let shown = await value(lesson) { $0.text.contains("不合适") }
      #expect(shown != nil)

      let file = try place.store.mentorFolder(first.mentor).appending(path: "lessons/filter.md")
      try place.edit(file) { $0.replacing("不合适", with: "资源不够") }

      let revised = await value(lesson) { $0.text.contains("资源不够") }
      #expect(revised != nil)
    }
  }
}
