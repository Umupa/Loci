import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

@MainActor
@Suite(.onStage)
struct ReaderTableTests {
  private static let longCell =
    "CubeHypervisor（Cloud Hypervisor 的 fork，以库的形式跑在 CubeShim 进程里，负责启动和恢复 MicroVM）"

  static let markdown = """
    ## 三个项目在这张图上的位置

    | 层 | CubeSandbox | E2B runtime | SPACE |
    | --- | --- | --- | --- |
    | VMM | \(longCell) | Firecracker | Firecracker |
    | 网络 | CubeVS | nftables | 出网策略 |

    继续读正文。
    """

  @Test func aNarrowTableWrapsWithinItsColumnsAndKeepsItsRowsAligned() throws {
    let (coordinator, scrollView, window) = ReaderTests.reader(heard: ReaderTests.Heard())
    defer { window.orderOut(nil) }
    let text = ReadingText(markdown: Self.markdown, serif: true)
    coordinator.show(text, from: nil)
    let note = try PlacedNoteTests.note("CubeHypervisor", thought: "以后再看")
    coordinator.mark(PlacedNote.marks(PlacedNote.place([note], in: text)))
    let view = try #require(scrollView.documentView as? ReaderTextView)

    for width: CGFloat in [980, 470, 680] {
      window.setContentSize(CGSize(width: width, height: 700))
      let manager = try #require(view.textLayoutManager)
      let storage = try #require(view.contentStorage)
      manager.ensureLayout(for: storage.documentRange)
      view.layOutViewport()
      let table = try #require(view.tables.allObjects.first(where: { $0.window === window }))

      func rects(_ words: String) -> [CGRect] {
        let range = (table.string as NSString).range(of: words)
        guard range.location != NSNotFound else { return [] }
        return table.rects(of: range).map { table.convert($0, to: view) }
      }

      let head = try ["层", "CubeSandbox", "E2B runtime", "SPACE"].map { try #require(rects($0).first) }
      #expect(zip(head, head.dropFirst()).allSatisfy { $0.minX < $1.minX })
      #expect(head.allSatisfy { abs($0.minY - head[0].minY) < 2 })
      let body = rects(Self.longCell)
      try #require(body.count > 1)
      #expect(body.allSatisfy { $0.minX >= head[1].minX - 1 && $0.maxX <= head[2].minX })
      let next = try #require(rects("nftables").first)
      #expect(abs(next.minX - head[2].minX) < 2)
      #expect(next.minY > (body.last?.maxY ?? .infinity))
      let after = try #require(view.rects(of: (text.plain as NSString).range(of: "继续读正文。")).first)
      #expect(after.minY > next.maxY)

      let firstWord = (table.string as NSString).range(of: "CubeHypervisor")
      let layout = try #require(table.layoutManager)
      let color = layout.temporaryAttribute(.backgroundColor, atCharacterIndex: firstWord.location, effectiveRange: nil)
      #expect(color as? NSColor == Tones.readerMark)
      #expect(table.subviews.contains { $0 is NoteDot })
    }

    let quote = try TextQuote("网络\tCubeVS\tnftables\t出网策略")
    #expect(text.range(of: quote) != nil)

    let board = NSPasteboard(name: NSPasteboard.Name("loci-test-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    view.setSelectedRange(text.string.fullRange)
    #expect(view.writeSelection(to: board, type: .string))
    #expect(board.string(forType: .string) == text.original)
  }

  @Test func aTableWiderThanTheColumnCanScrollToItsLastCell() async throws {
    let (coordinator, scrollView, window) = ReaderTests.reader(heard: ReaderTests.Heard())
    defer { window.orderOut(nil) }
    window.orderBack(nil)
    window.setContentSize(CGSize(width: 470, height: 700))
    let cells = (1...10).map { "Column \($0)" }
    let header = "| " + cells.joined(separator: " | ") + " |"
    let rule = "| " + cells.map { _ in "---" }.joined(separator: " | ") + " |"
    let text = ReadingText(markdown: header + "\n" + rule + "\n" + header + "\n\nAfter the table.")
    coordinator.show(text, from: nil)
    let reader = try #require(scrollView.documentView as? ReaderTextView)
    try await eventually("the reader to show the table") {
      reader.layOutViewport()
      return reader.tables.allObjects.contains { $0.window === window }
    }
    let table = try #require(reader.tables.allObjects.first(where: { $0.window === window }))
    let scroll = try #require(table.enclosingScrollView)
    #expect(scroll.hasHorizontalScroller)

    let range = (table.string as NSString).range(of: "Column 10")
    let cell = try #require(table.rects(of: range).first)
    #expect(!table.visibleRect.contains(cell))
    scroll.contentView.scroll(to: CGPoint(x: table.bounds.maxX - scroll.contentSize.width, y: 0))
    #expect(table.visibleRect.contains(cell))
    #expect(scrollView.contentView.bounds.minX == 0)
  }

  @Test(arguments: [false, true])
  func theReaderReopensAtTheSavedRowInsideATable(nested: Bool) async throws {
    let (coordinator, _, window) = ReaderTests.reader(heard: ReaderTests.Heard())
    defer { window.orderOut(nil) }
    window.orderBack(nil)
    let rows = (1...70).map { "| Row \($0) | Detailed notes |" }.joined(separator: "\n")
    let table = "| Part | Notes |\n| --- | --- |\n" + rows
    let markdown = nested ? "- " + table.replacingOccurrences(of: "\n", with: "\n  ") : table
    let text = ReadingText(markdown: "## Comparison\n\n" + markdown)
    coordinator.show(text, from: try TextQuote("Row 42\tDetailed notes"))

    try await eventually("the saved row to be at the top", within: .seconds(5)) {
      coordinator.topQuote()?.text == "Row 42\tDetailed notes"
    }
  }
}

@MainActor
@Suite(.onStage)
struct ReaderTableSnapshots {
  @Test(arguments: Snapshot.Appearance.allCases)
  func narrowTable(appearance: Snapshot.Appearance) async throws {
    let view = Reader(
      text: ReadingText(markdown: ReaderTableTests.markdown, serif: true), start: nil,
      events: ReaderEvents(), passageBar: PassagePopover())
    try await ScreenSnapshots.shoot(
      "reader-narrow-table", view, appearance: appearance, size: CGSize(width: 480, height: 520))
  }
}
