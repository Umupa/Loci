import Foundation
import LociModel
import SwiftUI

/// The person's edits to a panel that the host has not shown back yet, so each shows the moment it is made.
struct PendingEdits: Equatable {
  private(set) var edits: [PanelEdit] = []

  mutating func add(_ edit: PanelEdit) {
    edits.append(edit)
  }

  mutating func drop(_ edit: PanelEdit) {
    if let index = edits.firstIndex(of: edit) { edits.remove(at: index) }
  }

  /// The host's panel with the edits still on their way made on it.
  func shown(over panel: Panel) -> Panel {
    edits.reduce(panel) { shown, edit in (try? shown.applying(edit)) ?? shown }
  }

  /// Forgets the edits the host's panel already has.
  mutating func settle(on panel: Panel) {
    edits.removeAll { edit in
      switch edit {
      case .put: (try? panel.applying(edit)) == panel
      case .remove(let id): panel.place(of: id) == nil
      }
    }
  }
}

/// Loci's items new to a panel since it was last shown, ringed in amber for a moment.
enum Arrivals {
  static func new(in panel: Panel, since before: Panel?) -> Set<String> {
    guard let before else { return [] }
    let known = Set(before.sections.flatMap { $0.items.map(\.id) })
    return Set(panel.sections.flatMap { $0.items.filter { $0.by == .loci && !known.contains($0.id) }.map(\.id) })
  }
}

/// One panel's edits as the person makes them: shown at once, sent to the host, and each with its undo.
@MainActor
@Observable
final class PanelEditor {
  private(set) var pending = PendingEdits()
  /// Loci's items that just came in.
  private(set) var arrived: Set<String>
  /// How long an item that came in stays ringed.
  static let ringed = Duration.milliseconds(2400)
  @ObservationIgnored private var latest: Panel?
  @ObservationIgnored private weak var undoManager: UndoManager?

  init(arrived: Set<String> = []) {
    self.arrived = arrived
  }

  func shown(_ panel: Panel) -> Panel {
    pending.shown(over: panel)
  }

  /// Takes in the host's panel as it is now.
  func settle(on panel: Panel) {
    let new = Arrivals.new(in: panel, since: latest)
    latest = panel
    pending.settle(on: panel)
    guard !new.isEmpty else { return }
    arrived.formUnion(new)
    Task {
      try? await Task.sleep(for: Self.ringed)
      arrived.subtract(new)
    }
  }

  /// Makes the edit on the panel as shown, and registers the edit that takes it back.
  func make(_ edit: PanelEdit, send: @escaping @MainActor (PanelEdit) async -> Bool, undoManager: UndoManager?) {
    self.undoManager = undoManager
    guard let latest else { return }
    let shown = shown(latest)
    guard (try? shown.applying(edit)) != nil, let back = edit.reverse(in: shown) else { return }
    pending.add(edit)
    Task {
      if await !send(edit) { pending.drop(edit) }
    }
    undoManager?.registerUndo(withTarget: self) { editor in
      MainActor.assumeIsolated { editor.make(back, send: send, undoManager: editor.undoManager) }
    }
  }

  /// Keeps the person's take on a list line, and registers the take it had before.
  func mark(
    _ line: PanelLineKey, _ mark: PanelLineMark, was: PanelLineMark,
    send: @escaping @MainActor (PanelLineKey, PanelLineMark) async -> Bool, undoManager: UndoManager?
  ) {
    self.undoManager = undoManager
    Task { _ = await send(line, mark) }
    undoManager?.registerUndo(withTarget: self) { editor in
      MainActor.assumeIsolated { editor.mark(line, was, was: mark, send: send, undoManager: editor.undoManager) }
    }
  }
}

/// What a panel's rows can do to the panel they are in; without it, they only show.
struct PanelEditing {
  /// The panel as shown, with the edits on their way made on it.
  let panel: Panel
  let make: (PanelEdit) -> Void
  let mark: (PanelLineKey, PanelLineMark) -> Void
  /// The id of an item the person adds.
  let newID: () -> String
  /// Loci's items that just came in, ringed in amber for a moment.
  var arrived: Set<String> = []
  /// The person's take on the lines of the panel's lists.
  var marks: [PanelLineKey: PanelLineMark] = [:]
}

extension EnvironmentValues {
  @Entry var panelEditing: PanelEditing?
}
