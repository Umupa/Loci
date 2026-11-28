import Foundation
import SwiftUI

/// The window's latest deletion, while the notice at the foot of the library can still bring it back. Items
/// are deleted from the library and from an item's own page, and follows are stopped from the row or their
/// page; either way the notice shows in the library and ⌘Z undoes it.
@MainActor
@Observable
final class Deletions {
  private(set) var latest: Deletion?
  @ObservationIgnored private var restore: () -> Void = {}
  @ObservationIgnored private weak var undoManager: UndoManager?

  struct Deletion: Equatable {
    let id = UUID()
    /// What the notice says went.
    let words: LocalizedStringResource

    static func == (one: Deletion, other: Deletion) -> Bool { one.id == other.id }
  }

  /// `count` items went; `restore` brings them back, from the notice or from ⌘Z.
  func happened(_ count: Int, undoManager: UndoManager?, restore: @escaping () -> Void) {
    happened(
      .loci("library.deleted \(count)"), action: .loci("item.delete"), undoManager: undoManager, restore: restore)
  }

  /// Something went that the notice names in `words`, and ⌘Z names `action`.
  func happened(
    _ words: LocalizedStringResource, action: LocalizedStringResource, undoManager: UndoManager?,
    restore: @escaping () -> Void
  ) {
    self.undoManager?.removeAllActions(withTarget: self)
    latest = Deletion(words: words)
    self.restore = restore
    self.undoManager = undoManager
    undoManager?.registerUndo(withTarget: self) { deletions in
      MainActor.assumeIsolated { deletions.undo() }
    }
    undoManager?.setActionName(String(localized: action))
  }

  func undo() {
    undoManager?.removeAllActions(withTarget: self)
    guard latest != nil else { return }
    latest = nil
    restore()
  }

  /// The notice has been up long enough; the deletion can still be undone with ⌘Z until the next one.
  func settle(_ deletion: Deletion) {
    if latest == deletion { latest = nil }
  }
}

extension EnvironmentValues {
  /// Set by the window.
  @Entry var deletions: Deletions?
}
