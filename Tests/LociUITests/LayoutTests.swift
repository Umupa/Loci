import CoreGraphics
import Testing

@testable import LociUI

@Suite struct LayoutTests {
  @Test func aComfortableColumnKeepsItsMeasureInAWideWindow() {
    let width = Typography.readingWidth + 600
    #expect(ReadingWidth.comfortable.margin(in: width) == 300)
  }

  @Test func aFullWidthColumnFillsTheSpaceBetweenThePanes() {
    let width = Typography.readingWidth + 600
    #expect(ReadingWidth.full.margin(in: width) == Spacing.xxl)
  }

  @Test func bothColumnsKeepAMarginInANarrowWindow() {
    #expect(ReadingWidth.comfortable.margin(in: 300) == Spacing.xxl)
    #expect(ReadingWidth.full.margin(in: 300) == Spacing.xxl)
  }

  @Test func aDraggedPaneStopsAtItsNarrowestAndWidest() {
    let pane = PaneWidth.sidebar
    #expect(pane.clamped(0) == pane.range.lowerBound)
    #expect(pane.clamped(10_000) == pane.range.upperBound)
    #expect(pane.clamped(pane.ideal) == pane.ideal)
  }

  @Test func thePanelCanTakeAllButTheRoomTheTextNeeds() {
    let pane = PaneWidth.panel
    let window: CGFloat = 1_000
    let room: CGFloat = window - Size.readerMinimum
    #expect(pane.fitting(2_000, in: window) == room)
    #expect(pane.fitting(500, in: window) == 500)
  }

  @Test func aPanelInANarrowWindowKeepsItsNarrowestWidth() {
    let pane = PaneWidth.panel
    #expect(pane.fitting(500, in: 400) == pane.range.lowerBound)
  }

  @Test func theSidebarGrowsDraggedRightAndThePanelGrowsDraggedLeft() {
    #expect(PaneWidth.sidebar.width(from: 240, dragged: 20) == 260)
    #expect(PaneWidth.panel.width(from: 384, dragged: -20) == 404)
  }
}
