import Foundation
import Testing

@testable import LociModel

struct CatalogTests {
  static func slug(_ text: String) throws -> Lesson.Slug { try #require(Lesson.Slug(text)) }

  @Test func catalogSurvivesJSON() throws {
    let catalog = try Catalog(chapters: [
      .init(
        title: "调度",
        lessons: [
          try Lesson(slug: Self.slug("filter"), title: "过滤"), try Lesson(slug: Self.slug("score"), title: "打分"),
        ]),
      .init(title: "还没写", lessons: []),
    ])

    #expect(try Fixture.roundTrip(catalog) == catalog)
  }

  @Test func anEmptyCatalogIsValid() throws {
    #expect(try Fixture.decode(Catalog.self, "{}").chapters.isEmpty)
  }

  @Test func aLessonCannotAppearTwice() throws {
    let lesson = try Lesson(slug: Self.slug("intro"), title: "Intro")
    #expect(throws: ModelError.self) {
      try Catalog(chapters: [.init(title: "A", lessons: [lesson]), .init(title: "B", lessons: [lesson])])
    }
    #expect(throws: DecodingError.self) {
      try Fixture.decode(
        Catalog.self,
        #"{"chapters":[{"title":"A","lessons":[{"slug":"x","title":"1"},{"slug":"x","title":"2"}]}]}"#)
    }
  }

  @Test func titlesAreNotBlank() throws {
    #expect(throws: ModelError.self) { try Catalog.Chapter(title: " ", lessons: []) }
    #expect(throws: ModelError.self) { try Lesson(slug: Self.slug("a"), title: "") }
  }

  @Test(arguments: ["intro", "k8s-scheduling-01", "a--b", "1"])
  func slugsAreWhatAMentorCanWriteByHand(text: String) {
    #expect(Lesson.Slug(text)?.description == text)
  }

  @Test(arguments: ["", "-intro", "intro-", "Intro", "in tro", "in_tro", "调度", "a/b"])
  func slugsThatCannotBeFileNamesAreRejected(text: String) {
    #expect(Lesson.Slug(text) == nil)
  }

  @Test func sourcesAreItemsOrLinksToFetch() throws {
    let front = try Fixture.decode(
      Lesson.Front.self, #"{"sources":["\#(Fixture.item)","https://arxiv.org/abs/1234"]}"#)

    #expect(front.sources == [.item(Fixture.item), .link(try #require(URL(string: "https://arxiv.org/abs/1234")))])
    #expect(try Fixture.roundTrip(front) == front)
  }

  @Test func anItemSourceIsReadOnlyInItsCanonicalForm() {
    #expect(Lesson.Source(Fixture.item.description) == .item(Fixture.item))
    #expect(Lesson.Source(Fixture.item.description.uppercased()) == nil)
  }

  @Test(arguments: [#"["notes.md"]"#, #"["ftp://x.org/a"]"#, #"["\#(Fixture.item)","\#(Fixture.item)"]"#])
  func sourcesThatAreNeitherOrRepeatedAreRejected(sources: String) {
    #expect(throws: DecodingError.self) { try Fixture.decode(Lesson.Front.self, #"{"sources":\#(sources)}"#) }
  }
}
