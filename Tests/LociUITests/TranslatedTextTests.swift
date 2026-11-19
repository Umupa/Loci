import AppKit
import LociModel
import Testing

@testable import LociUI

/// An article set with its translation beside or in place of each passage (T-S3, T-S4).
@MainActor
struct TranslatedTextTests {
  static let markdown = """
    # The Tail at Scale

    Systems that respond **quickly** feel more fluid.

    ```
    let x = 1
    ```

    - Shared resources
    """

  static let translation = ShownTranslation(
    passages: [
      "# The Tail at Scale": "# 规模化下的长尾", "Systems that respond **quickly** feel more fluid.": "响应**快**的系统用起来更流畅。",
      "Shared resources": "共享资源",
    ], mode: .both)

  static func text(_ mode: SubtitleMode?) -> ReadingText {
    ReadingText(
      markdown: markdown,
      translation: mode.map { ShownTranslation(passages: translation.passages, mode: $0) })
  }

  @Test func theOriginalAloneReadsAsIfThereWereNoTranslation() {
    #expect(Self.text(.original).plain == Self.text(nil).plain)
  }

  @Test func sideBySideEachTranslationFollowsItsPassageAndCodeIsNotRepeated() {
    let plain = Self.text(.both).plain
    #expect(plain.contains("The Tail at Scale\n规模化下的长尾\n"))
    #expect(plain.contains("feel more fluid.\n响应快的系统用起来更流畅。\n"))
    #expect(plain.contains("共享资源"))
    #expect(plain.components(separatedBy: "let x = 1").count == 2)
  }

  @Test func theTranslationAloneHidesThePassagesItTranslates() {
    let plain = Self.text(.translation).plain
    #expect(!plain.contains("feel more fluid"))
    #expect(plain.contains("响应快的系统用起来更流畅。"))
    #expect(plain.contains("let x = 1"))
  }

  @Test func aQuoteFromTheOriginalIsFoundWhicheverWayTheArticleIsShown() throws {
    let quote = try #require(Self.text(nil).quote(Self.range(of: "respond quickly", in: Self.text(nil))))
    for mode in SubtitleMode.allCases {
      let text = Self.text(mode)
      let found = try #require(text.range(of: quote.quote))
      let shown = (text.plain as NSString).substring(with: found)
      #expect(shown == (mode == .translation ? "响应快的系统用起来更流畅。" : "respond quickly"))
    }
  }

  @Test func choosingWordsOfATranslationQuotesThePassageItTranslates() throws {
    for mode in [SubtitleMode.both, .translation] {
      let text = Self.text(mode)
      let passage = try #require(text.quote(Self.range(of: "流畅", in: text)))
      #expect(passage.excerpt == "Systems that respond quickly feel more fluid.")
      #expect(try #require(Self.text(nil).range(of: passage.quote)).length == passage.excerpt.utf16.count)
    }
  }

  @Test func wordsAfterATranslationKeepTheirPlace() throws {
    let original = Self.text(nil)
    let quote = try #require(original.quote(Self.range(of: "Shared", in: original)))
    let text = Self.text(.both)
    let found = try #require(text.range(of: quote.quote))
    #expect((text.plain as NSString).substring(with: found) == "Shared")
  }

  private static func range(of words: String, in text: ReadingText) -> NSRange {
    (text.plain as NSString).range(of: words)
  }
}
