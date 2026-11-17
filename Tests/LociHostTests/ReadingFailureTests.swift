import LociModel
import Testing

@testable import LociHost
@testable import LociStore

struct ReadingFailureTests {
  @Test func savingANewPositionKeepsTheReadMarkAndMarkingReadKeepsThePosition() async throws {
    try await withHost { host, place, _ in
      let (lesson, _) = try await LessonScenarioTests.mentorWithLessons(host, place)
      let content = ContentRef.lesson(lesson)
      let first = Locator.lesson(lesson, try TextQuote("不合适的节点"))
      #expect(try await host.run(ReadReadingState(content: content)) == nil)
      _ = try await host.run(SaveReadingPosition(content: content, position: first))
      _ = try await host.run(MarkRead(content: content))
      #expect(
        try await host.run(ReadReadingState(content: content))
          == ReadingState(position: first, finished: true, updatedAt: TestWorld.instant))
      let second = Locator.lesson(lesson, try TextQuote("先排除"))
      _ = try await host.run(SaveReadingPosition(content: content, position: second))
      #expect(
        try await host.run(ReadReadingState(content: content))
          == ReadingState(position: second, finished: true, updatedAt: TestWorld.instant))
    }
  }

  @Test func anInvalidPositionDoesNotOverwriteTheLastGoodOne() async throws {
    try await withHost { host, place, world in
      let (lesson, _) = try await LessonScenarioTests.mentorWithLessons(host, place)
      let content = ContentRef.lesson(lesson)
      let position = Locator.lesson(lesson, try TextQuote("节点"))
      _ = try await host.run(SaveReadingPosition(content: content, position: position))

      await #expect(throws: HostError.self) {
        try await host.run(
          SaveReadingPosition(content: content, position: .item(world.nextID(), .quote(try TextQuote("elsewhere")))))
      }
      #expect(try await host.run(ReadReadingState(content: content))?.position == position)
    }
  }

  @Test func aBrokenGlossaryAppearsInHealthAndRepairClearsIt() async throws {
    try await withHost { host, place, _ in
      let (lesson, _) = try await LessonScenarioTests.mentorWithLessons(host, place)
      let file = try place.store.mentorFolder(lesson.mentor).appending(path: "glossary.yaml")
      try place.edit(file) { _ in "terms:\n- term: node\n" }
      await host.follow([.mentor(lesson.mentor)])

      let broken = await value(host.subscribe(HealthReport())) { !$0.fileProblems.isEmpty }
      #expect(broken?.fileProblems.first?.subject == .mentor(lesson.mentor))
      #expect(broken?.fileProblems.first?.path.hasSuffix("glossary.yaml") == true)
      #expect(try await host.lessonPage(lesson).glossary == .empty)
      #expect(try await host.lessonPage(lesson).text.contains("节点"))
      try place.store.save(Glossary(terms: [.init(term: "node", definition: "A machine.")]), of: lesson.mentor)
      await host.follow([.mentor(lesson.mentor)])
      #expect(await value(host.subscribe(HealthReport())) { $0.fileProblems.isEmpty } != nil)
      #expect(try await host.lessonPage(lesson).glossary.terms.map(\.term) == ["node"])
    }
  }

  @Test func aLostPassageKeepsItsNoteAndCanBeDeleted() async throws {
    try await withHost { host, place, _ in
      let (lesson, _) = try await LessonScenarioTests.mentorWithLessons(host, place)
      let quote = try TextQuote("不合适的节点")
      let note = try await host.run(AddNote(locator: .lesson(lesson, quote), excerpt: quote.text, thought: "keep this"))
      try place.store.save(LessonText(front: try Lesson.Front(sources: []), body: "完全改写的课文。"), as: lesson)
      await host.follow([.lesson(lesson)])

      #expect(try quote.range(in: await host.lessonText(lesson)) == nil)
      #expect(try await host.notes(on: .lesson(lesson)) == [note])
      _ = try await host.run(DeleteNote(content: .lesson(lesson), note: note.id))
      #expect(try await host.notes(on: .lesson(lesson)).isEmpty)
    }
  }

  @Test func aFailedLessonReadDoesNotReplaceTheRevisionBaseline() async throws {
    try await withHost { host, place, _ in
      let (lesson, _) = try await LessonScenarioTests.mentorWithLessons(host, place)
      let before = try await host.lessonText(lesson)
      _ = try await host.run(SeeLesson(lesson: lesson))
      let file = try place.store.mentorFolder(lesson.mentor).appending(path: "lessons/\(lesson.lesson).md")
      try place.edit(file) { _ in "---\nsources: [\n---\nbroken" }
      await #expect(throws: HostError.self) { try await host.run(SeeLesson(lesson: lesson)) }
      try place.store.save(LessonText(front: try Lesson.Front(sources: []), body: "New text"), as: lesson)
      #expect(try await host.run(SeeLesson(lesson: lesson)) == before)
    }
  }
}
