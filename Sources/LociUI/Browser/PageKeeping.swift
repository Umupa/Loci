import Foundation
import LociModel
import SwiftUI

/// What was last kept from the page in front, for the library button and the note under it. The note comes
/// up once there is a result; a saved one goes away by itself, a stopped one stays until it is put away.
@MainActor
@Observable
final class PageKeeping {
  private(set) var keeping: Keeping?
  private(set) var noteUp = false

  /// How long the note that something was saved stays up.
  static let savedNoteTime = Duration.seconds(4)

  func keep(_ chosen: [PageFinds.Find], from tab: BrowserTab, by taker: PageTaker) {
    guard taker.changesAllowed else { return }
    let asked = Keeping(chosen: chosen)
    keeping = asked
    noteUp = false
    Task {
      await tab.point(at: nil)
      let taken = await taker.keep(chosen, from: tab)
      guard keeping == asked else { return }
      if taken.items.isEmpty, taken.refusal == nil {
        keeping = nil
        return
      }
      keeping?.took(taken.items, refusal: taken.refusal)
      noteUp = true
    }
  }

  /// Shows what `keeping` says with its note up, as a snapshot draws it.
  func stand(in keeping: Keeping) {
    self.keeping = keeping
    noteUp = true
  }

  func state(library: [Item]?, jobs: [Job]) -> Keeping.State? {
    keeping?.state(library: library, jobs: jobs)
  }

  func noting(_ library: [Item]) {
    keeping?.noting(library)
  }

  /// Brings the note back, when there is something it says.
  func showNote() {
    if keeping != nil { noteUp = true }
  }

  /// Puts the note away; once saved, there is nothing left to tell.
  func putAway(_ state: Keeping.State?) {
    noteUp = false
    if case .saved = state { keeping = nil }
  }

  /// Takes what was kept back out of the library.
  func undo(with host: any LociModel.Host) {
    let items = keeping?.items ?? []
    forget()
    guard !items.isEmpty else { return }
    Task { _ = try? await host.run(DeleteItems(items)) }
  }

  /// The page changed; what was kept from the last one is told in the library.
  func forget() {
    keeping = nil
    noteUp = false
  }
}
