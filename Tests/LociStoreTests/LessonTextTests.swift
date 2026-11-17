import Foundation
import LociModel
import Testing

@testable import LociStore

struct LessonTextTests {
  static let ref = LessonRef(mentor: Fixture.id(1), lesson: Fixture.slug("filter"))
  static let item = Fixture.id(2)
  static let other = Fixture.id(3)

  @Test func aFileWithoutFrontMatterIsAllBodyAndCitesNothing() throws {
    let lesson = try LessonText(parsing: "# Title\n\ntext\n")

    #expect(lesson.front.sources.isEmpty)
    #expect(lesson.body == "# Title\n\ntext\n")
  }

  @Test func frontMatterIsReadAndWrittenBack() throws {
    let text = "---\nsources:\n- \(Self.item)\n- https://example.com/paper\n---\n# Title\n"
    let lesson = try LessonText(parsing: text)

    #expect(lesson.front.sources == [.item(Self.item), .link(URL(string: "https://example.com/paper")!)])
    #expect(lesson.body == "# Title\n")
    #expect(try lesson.text() == text)
    #expect(
      try LessonText(parsing: "---\r\nsources: []\r\n---\r\nbody") == LessonText(parsing: "---\nsources: []\n---\nbody")
    )
  }

  @Test(arguments: ["---\nsources: [\n---\nbody", "---\nsources:\n- not-an-id\n---\n", "---\nsources: []\nbody"])
  func brokenFrontMatterIsAnError(text: String) {
    #expect(throws: (any Error).self) { try LessonText(parsing: text) }
  }

  @Test func citationsAreTheSourcesThenEachPlaceTheBodyPointsAt() throws {
    let lesson = try LessonText(
      parsing: """
        ---
        sources:
        - \(Self.item)
        - https://example.com/later
        ---
        Borg 先过滤（[原文](loci://library/\(Self.item)#quote=feasibility%20checking)），
        再打分 <loci://library/\(Self.other)#t=12,30> 和 loci://library/\(Self.item)#quote=feasibility%20checking 重复。
        见 [上一课](loci://mentor/\(Fixture.id(1))/lesson/intro#quote=x)。

        ```
        loci://library/\(Fixture.id(4))#quote=only-an-example
        ```
        """)

    let found = lesson.citations(in: Self.ref)

    #expect(
      found.citations == [
        Citation(lesson: Self.ref, item: Self.item, anchor: nil),
        Citation(lesson: Self.ref, item: Self.item, anchor: .quote(try TextQuote("feasibility checking"))),
        Citation(
          lesson: Self.ref, item: Self.other,
          anchor: .time(try TimeSpan(start: .seconds(12), end: .seconds(30)))),
      ])
    #expect(found.brokenLocators.isEmpty)
  }

  @Test func linksThatDoNotParseAreReportedNotDropped() throws {
    let lesson = try LessonText(parsing: "see [x](loci://library/\(Self.item)#t=5,4) and loci://nowhere/at-all")

    #expect(
      lesson.citations(in: Self.ref).brokenLocators == ["loci://library/\(Self.item)#t=5,4", "loci://nowhere/at-all"])
    #expect(lesson.citations(in: Self.ref).citations.isEmpty)
  }
}
