import AppKit
import LociModel

/// The items chosen in the library to act on together. A plain click opens an item and lets go of the rest;
/// ⌘-click adds or takes away one; Shift-click chooses everything between the last one clicked and this one.
struct LibrarySelection: Equatable {
  private(set) var chosen: Set<EntityID> = []
  private var anchor: EntityID?

  enum Click: Equatable {
    case open, toggle, extend

    @MainActor init(event: NSEvent?) {
      self.init(event?.type == .leftMouseUp || event?.type == .leftMouseDown ? event?.modifierFlags ?? [] : [])
    }

    init(_ modifiers: NSEvent.ModifierFlags) {
      if modifiers.contains(.command) {
        self = .toggle
      } else if modifiers.contains(.shift) {
        self = .extend
      } else {
        self = .open
      }
    }
  }

  /// Follows a click on `item`, with `order` the items as they are laid out. Whether to open it.
  mutating func click(_ item: EntityID, _ click: Click, in order: [EntityID]) -> Bool {
    switch click {
    case .open:
      clear()
      return true
    case .toggle:
      if chosen.remove(item) == nil { chosen.insert(item) }
      anchor = item
    case .extend:
      let from = anchor.flatMap(order.firstIndex) ?? order.firstIndex(of: item)
      guard let from, let to = order.firstIndex(of: item) else { return false }
      chosen.formUnion(order[min(from, to)...max(from, to)])
      anchor = anchor ?? item
    }
    return false
  }

  /// What a right click on `item` acts on: the chosen items when it is one of them, or else it alone.
  func acted(on item: EntityID) -> [EntityID] {
    chosen.contains(item) ? Array(chosen) : [item]
  }

  /// Lets go of items no longer in the library.
  mutating func keep(_ present: [EntityID]) {
    chosen.formIntersection(present)
    if let anchor, !present.contains(anchor) { self.anchor = nil }
  }

  mutating func clear() {
    chosen = []
    anchor = nil
  }
}
