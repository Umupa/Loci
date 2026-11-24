import Testing

@testable import LociModel

struct BookContentsTests {
  static let book = BookContents(
    chapters: [.init(path: "a", length: 100), .init(path: "b", length: 300), .init(path: "c", length: 600)],
    toc: [.init(title: "One", depth: 0, chapter: 0), .init(title: "Two", depth: 0, chapter: 2)], language: nil)

  @Test func aPlaceIsSharedOutByTheLengthOfTheChaptersBeforeIt() {
    #expect(Self.book.share(chapter: 0, within: 0) == Fraction(0))
    #expect(Self.book.share(chapter: 1, within: 0.5) == Fraction(0.25))
    #expect(Self.book.share(chapter: 2, within: 1) == Fraction(1))
  }

  @Test func aShareOfTheBookLeadsBackToItsChapter() throws {
    let place = try #require(Self.book.place(of: Fraction(0.25)))

    #expect(place.chapter == 1)
    #expect(place.within == Fraction(0.5))
    #expect(Self.book.place(of: Fraction(1))?.chapter == 2)
  }

  @Test func aChapterBelongsToTheLastEntryThatStartsAtOrBeforeIt() {
    #expect(Self.book.entry(for: 1)?.title == "One")
    #expect(Self.book.entry(for: 2)?.title == "Two")
  }
}
