import AppKit
import LociModel
import Testing

@testable import LociUI

/// HL-S2, HL-S3: highlights over the pictures of an article.
@MainActor
struct PicturePassageTests {
  static let item = EntityID()
  static let markdown = """
    # Timers

    Timers live in their own store.

    ![](images/timers.png)

    The inbox only holds what is ready.
    """

  static let picture = NSImage(size: NSSize(width: 600, height: 300), flipped: false) { _ in true }

  static func text(_ mode: SubtitleMode? = nil) -> ReadingText {
    ReadingText(
      markdown: markdown, images: ["images/timers.png": picture],
      translation: mode.map {
        ShownTranslation(
          passages: [
            "Timers live in their own store.": "定时器有自己的存储。", "The inbox only holds what is ready.": "收件箱只放到点的事。",
          ],
          mode: $0)
      })
  }

  static func range(of words: String, in text: ReadingText) -> NSRange {
    (text.plain as NSString).range(of: words)
  }

  static func pictureRange(in text: ReadingText) -> NSRange {
    range(of: "\u{FFFC}", in: text)
  }

  @Test func wordsAroundAPictureAreQuotedWithThePictureNamed() throws {
    let text = Self.text()
    let start = Self.range(of: "their own store", in: text)
    let end = Self.range(of: "The inbox", in: text)
    let passage = try #require(text.quote(NSRange(location: start.location, length: NSMaxRange(end) - start.location)))

    #expect(passage.pictures == ["images/timers.png"])
    #expect(passage.excerpt?.contains("\u{FFFC}") == false)
    #expect(passage.excerpt?.hasPrefix("their own store.") == true)
    #expect(passage.excerpt?.hasSuffix("The inbox") == true)
  }

  @Test func aPictureAloneIsQuotedWithoutWords() throws {
    let text = Self.text()
    let passage = try #require(text.quote(Self.pictureRange(in: text)))

    #expect(passage.pictures == ["images/timers.png"])
    #expect(passage.excerpt == nil)
  }

  @Test func aHighlightOnAPictureIsFoundWhicheverWayTheArticleIsShown() throws {
    let original = Self.text()
    let passage = try #require(original.quote(Self.pictureRange(in: original)))
    let note = try Note(
      id: EntityID(), locator: .item(Self.item, .quote(passage.quote)), pictures: passage.pictures,
      savedAt: Timestamp(millisecondsSince1970: 0))

    for mode in [nil] + SubtitleMode.allCases.map(Optional.some) {
      let text = Self.text(mode)
      let placed = try #require(PlacedNote.place([note], in: text).first)
      let range = try #require(placed.range)
      #expect((text.plain as NSString).substring(with: range) == "\u{FFFC}")
      #expect(placed.pictures == ["images/timers.png"])
      #expect(PlacedNote.marks([placed]).first?.picture == true)
    }
  }

  @Test func aHighlightSavedBeforePicturesFindsItsPictureInTheText() throws {
    let text = Self.text()
    let passage = try #require(text.quote(Self.pictureRange(in: text)))
    let old = try Note(
      id: EntityID(), locator: .item(Self.item, .quote(passage.quote)), excerpt: "\u{FFFC}",
      savedAt: Timestamp(millisecondsSince1970: 0))

    let placed = try #require(PlacedNote.place([old], in: text).first)

    #expect(placed.pictures == ["images/timers.png"])
    #expect(placed.words == nil)
  }
}

extension NoteActions {
  /// For a bar whose actions a test does not follow.
  @MainActor static let ignored = NoteActions(think: { _, _ in }, ask: nil, delete: { _ in })
}
