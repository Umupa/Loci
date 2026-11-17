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
    let mark = PaletteTests.components(of: Palette.mark, in: appearance)
    let distance = zip(selection, mark).map { abs($0 - $1) }.max() ?? 0

    #expect(distance > 0.1)
    #expect((selection.max() ?? 0) - (selection.min() ?? 0) < 0.06)
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
    let marks = [ReaderMark(kind: .note(EntityID(), marginMark: false), range: range)]
    coordinator.mark(marks)
    let textView = try #require(scrollView.documentView as? ReaderTextView)
    textView.displayIfNeeded()

    textView.placeMarginMarks(marks)

    #expect(!textView.needsDisplay)
  }

  @Test func aHighlightCoversTheLowerPartOfTheLettersOnEveryLine() throws {
    let textView = ReaderTextView()
    textView.frame = CGRect(x: 0, y: 0, width: 400, height: 2_000)
    let text = ReadingText(markdown: String(repeating: "Bytes wait in a queue the terminal driver owns. ", count: 12))
    textView.textStorage?.setAttributedString(text.string)
    textView.layOutViewport()
    let font = ReadingStyle.body
    let lines = textView.segments(of: NSRange(location: 0, length: (text.plain as NSString).length))
    try #require(lines.count > 2)

    for line in lines {
      let band = ReaderTextView.band(under: line.rect, baseline: line.baseline, font: font)
      #expect(band.minY > line.baseline - font.xHeight)
      #expect(band.maxY > line.baseline)
      #expect(band.maxY < line.baseline - font.descender)
      #expect(line.rect.contains(CGPoint(x: line.rect.midX, y: band.midY)))
    }
  }
}
