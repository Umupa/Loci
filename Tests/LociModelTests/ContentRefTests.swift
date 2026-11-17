import Testing

@testable import LociModel

struct ContentRefTests {
  @Test func aLocatorKnowsWhichContentItPointsInto() throws {
    let lesson = LessonRef(mentor: Fixture.mentor, lesson: try #require(Lesson.Slug("intro")))
    let quote = try TextQuote("x")

    #expect(Locator.item(Fixture.item, .quote(quote)).content == .item(Fixture.item))
    #expect(Locator.lesson(lesson, quote).content == .lesson(lesson))
  }
}
