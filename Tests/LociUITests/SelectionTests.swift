import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// Selecting a passage in the reader: the selection stands apart from highlights, and the bar over it leaves
/// the lines that follow in view.
@MainActor
struct SelectionTests {
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func aSelectionDoesNotLookLikeAHighlight(appearance: NSAppearance.Name) {
    let selection = PaletteTests.components(of: Palette.selection, in: appearance)
    let mark = PaletteTests.components(of: Color(nsColor: Tones.readerMark), in: appearance)

    #expect((selection.max() ?? 0) - (selection.min() ?? 0) < 0.06)
    #expect((mark.max() ?? 0) - (mark.min() ?? 0) > 0.1)
  }

  @Test func savedHighlightsStandOutOnDarkPaper() {
    let mark = PaletteTests.components(of: Color(nsColor: Tones.readerMark), in: .darkAqua)
    let paper = PaletteTests.components(of: Palette.canvas, in: .darkAqua)

    #expect(PaletteTests.contrast(mark, paper) >= 1.8)
  }

  static let bar = CGSize(width: 180, height: 36)
  static let visible = CGRect(x: 0, y: 1000, width: 800, height: 600)

  @Test func theBarSitsAboveTheSelectionSoTheLinesAfterItStayInView() {
    let first = CGRect(x: 300, y: 1300, width: 200, height: 30)
    let last = CGRect(x: 100, y: 1360, width: 150, height: 30)

    let frame = PassagePopover.frame(of: Self.bar, over: [first, last], within: Self.visible)

    #expect(frame.maxY <= first.minY)
    #expect(frame.minX == first.minX)
  }

  @Test func theBarGoesUnderTheSelectionWhenThereIsNoRoomAboveIt() {
    let line = CGRect(x: 100, y: 1010, width: 200, height: 30)

    let frame = PassagePopover.frame(of: Self.bar, over: [line], within: Self.visible)

    #expect(frame.minY >= line.maxY)
  }

  @Test func theBarStaysWithinTheVisibleText() {
    let line = CGRect(x: 760, y: 1300, width: 30, height: 30)

    let frame = PassagePopover.frame(of: Self.bar, over: [line], within: Self.visible)

    #expect(frame.maxX <= Self.visible.maxX)
  }

  @Test func placingMarksThatDidNotMoveRedrawsNothing() throws {
    let (coordinator, scrollView, window) = ReaderTests.reader(heard: ReaderTests.Heard())
    defer { window.orderOut(nil) }
    let text = ReadingText(markdown: ReaderTests.long)
    coordinator.show(text, from: nil)
    let range = (text.plain as NSString).range(of: "第 2 段")
    let marks = [ReaderMark(note: EntityID(), marginMark: false, range: range)]
    coordinator.mark(marks)
    let textView = try #require(scrollView.documentView as? ReaderTextView)
    textView.displayIfNeeded()

    textView.placeMarginMarks(marks)

    #expect(!textView.needsDisplay)
  }

  @Test func aHighlightCoversTheFullHeightOfTheLettersOnEveryLine() throws {
    let textView = ReaderTextView()
    textView.frame = CGRect(x: 0, y: 0, width: 400, height: 2_000)
    let body = String(repeating: "Bytes wait in a queue the terminal driver owns. ", count: 12)
    let text = ReadingText(markdown: "# Heading\n\n" + body, serif: true)
    textView.textStorage?.setAttributedString(text.string)
    textView.layOutViewport()
    let lines = textView.segments(of: NSRange(location: 0, length: (text.plain as NSString).length))
    try #require(lines.count > 2)
    let last = try #require(lines.last)
    #expect(last.location > "Heading".utf16.count)

    for line in lines where line.rect.width > 0 {
      let font = try #require(text.string.attribute(.font, at: line.location, effectiveRange: nil) as? NSFont)
      let band = ReaderTextView.band(behind: line.rect, baseline: line.baseline, font: font)
      #expect(band.minY <= line.baseline - font.capHeight + 0.5)
      #expect(band.maxY >= line.baseline - font.descender - 0.5)
      #expect(band.minY >= line.rect.minY)
      #expect(band.maxY <= line.rect.maxY)
    }
  }

  @Test func aNoteDotSitsBelowItsHighlightWhenMoreWordsFollowOnTheSameLine() throws {
    let textView = ReaderTextView()
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 200)
    let text = ReadingText(markdown: "The end of the excerpt. More words on the same line.", serif: true)
    textView.textStorage?.setAttributedString(text.string)
    textView.layOutViewport()
    let range = (text.plain as NSString).range(of: "The end of the excerpt.")
    let line = try #require(textView.segments(of: range).last)
    let font = try #require(text.string.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)

    textView.placeMarginMarks([ReaderMark(note: EntityID(), marginMark: true, range: range)])

    let dot = try #require(textView.subviews.compactMap { $0 as? NoteDot }.first)
    let band = ReaderTextView.band(behind: line.rect, baseline: line.baseline, font: font)
    #expect(dot.frame.minY > band.maxY)
    #expect(abs(dot.frame.midX - band.maxX) <= dot.frame.width)
  }
}
