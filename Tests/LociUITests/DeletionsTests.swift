import AppKit
import Testing

@testable import LociUI

/// A-S9 and I-S7: one deletion notice for the window, whether items went from the library or from their page.
@MainActor
struct DeletionsTests {
  @Test func undoingBringsTheItemsBackOnceAndTakesTheNoticeAway() {
    let deletions = Deletions()
    var restored = 0

    deletions.happened(2, undoManager: nil) { restored += 1 }
    #expect(deletions.latest?.count == 2)
    deletions.undo()
    deletions.undo()

    #expect(restored == 1)
    #expect(deletions.latest == nil)
  }

  @Test func commandZUndoesTheLatestDeletionFromAnyPage() {
    let deletions = Deletions()
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var restored: [Int] = []

    undoManager.beginUndoGrouping()
    deletions.happened(1, undoManager: undoManager) { restored.append(1) }
    undoManager.endUndoGrouping()
    undoManager.beginUndoGrouping()
    deletions.happened(3, undoManager: undoManager) { restored.append(3) }
    undoManager.endUndoGrouping()
    undoManager.undo()

    #expect(restored == [3])
    #expect(deletions.latest == nil)
  }

  @Test func theNoticeLeavesOnlyIfNoNewerDeletionCameMeanwhile() throws {
    let deletions = Deletions()
    deletions.happened(1, undoManager: nil) {}
    let first = try #require(deletions.latest)
    deletions.happened(2, undoManager: nil) {}

    deletions.settle(first)

    #expect(deletions.latest?.count == 2)
  }
}
