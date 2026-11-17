import Foundation
import Testing

@testable import LociModel

struct CitationTests {
  static let lesson = LessonRef(mentor: Fixture.mentor, lesson: Lesson.Slug("intro")!)

  @Test func aLessonCitesTheItemsInItsSourcesButNotLinksStillToFetch() throws {
    let other = Fixture.id(9)
    let front = try Lesson.Front(sources: [
      .item(Fixture.item), .link(try #require(URL(string: "https://example.com"))), .item(other),
    ])

    #expect(
      front.citations(in: Self.lesson) == [
        Citation(lesson: Self.lesson, item: Fixture.item, anchor: nil),
        Citation(lesson: Self.lesson, item: other, anchor: nil),
      ])
  }

  @Test func aLocatorInTheTextCitesThePlaceItPointsAt() throws {
    let anchor = ItemAnchor.time(try TimeSpan(start: .seconds(3)))

    #expect(
      Citation(in: Self.lesson, pointingAt: .item(Fixture.item, anchor))
        == Citation(lesson: Self.lesson, item: Fixture.item, anchor: anchor))
  }

  @Test func aLocatorIntoAnotherLessonCitesNoItem() throws {
    #expect(Citation(in: Self.lesson, pointingAt: .lesson(Self.lesson, try TextQuote("x"))) == nil)
  }
}
