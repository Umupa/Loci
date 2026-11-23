import Foundation
import LociModel
import SwiftUI

/// How a section shows its items: those still to do, pinned first, and those done, folded into dots.
struct SectionShape {
  let active: [PanelItem]
  let done: [PanelItem]

  /// `lingering` items were just ticked and stay where they were a moment before they sink.
  init(_ section: PanelItems, lingering: Set<String> = []) {
    let open = section.items.filter { !$0.done || lingering.contains($0.id) }
    active = open.filter(\.pinned) + open.filter { !$0.pinned }
    done = section.items.filter { $0.done && !lingering.contains($0.id) }
  }
}

/// The rows a section draws for its items still to do while one may be dragged. The dragged item keeps its
/// row, unseen, wherever the hollow is: the drag lives on that row, and taking the row out would end the drag
/// without its end and hand the pointer to the panel's own drag.
struct SectionRows: Equatable {
  enum Row: Equatable {
    case item(PanelItem)
    case carried(PanelItem)
    /// Where the dragged item would land.
    case hollow
  }

  let rows: [Row]

  /// `hollow` is the place among the other items still to do where the dragged item would land in this
  /// section, or `nil` when it would land elsewhere.
  init(_ shape: SectionShape, carrying id: String?, hollow: Int?) {
    var rows: [Row] = []
    var others = 0
    for item in shape.active {
      if item.id == id {
        rows.append(.carried(item))
        continue
      }
      if others == hollow { rows.append(.hollow) }
      rows.append(.item(item))
      others += 1
    }
    if let hollow, hollow >= others {
      if case .carried = rows.last {
        rows.insert(.hollow, at: rows.count - 1)
      } else {
        rows.append(.hollow)
      }
    }
    self.rows = rows
  }
}

/// How far along the first section that can be ticked is, shown as a ring before the panel's title.
struct CheckProgress: Equatable {
  let done: Int
  let all: Int

  init(done: Int, all: Int) {
    self.done = done
    self.all = all
  }

  /// `nil` when nothing in the panel can be ticked.
  init?(_ panel: Panel) {
    guard let section = panel.sections.first(where: \.checks) else { return nil }
    done = section.items.count(where: \.done)
    all = section.items.count
  }

  var fraction: Double { all == 0 ? 0 : Double(done) / Double(all) }
  var isFull: Bool { all > 0 && done == all }
}

/// Where a dragged item lands among the items still to do in a section.
enum ItemDrop {
  /// How many of the rows, top to bottom, are above `y`.
  static func index(at y: CGFloat, among rows: [CGRect]) -> Int {
    rows.count { $0.midY < y }
  }

  /// The edit that puts `item` before the `index`th item still to do in the section, or after the last.
  static func edit(_ item: PanelItem, into section: PanelItems, at index: Int) -> PanelEdit {
    let others = section.items.filter { $0.id != item.id }
    let shown = SectionShape(PanelItems(id: section.id, items: others)).active
    let at: Int
    if shown.indices.contains(index), let before = others.firstIndex(where: { $0.id == shown[index].id }) {
      at = before
    } else {
      at = shown.last.flatMap { last in others.firstIndex { $0.id == last.id } }.map { $0 + 1 } ?? 0
    }
    return .put(item, section: section.id, at: at)
  }
}

/// What right-clicking an item offers.
enum PanelItemMenu: Equatable {
  case pin, unpin, note, editNote, take, remove

  static func entries(for item: PanelItem) -> [PanelItemMenu] {
    [item.pinned ? .unpin : .pin, item.note == nil ? .note : .editNote] + (item.by == .loci ? [.take] : [])
      + [.remove]
  }

  var name: LocalizedStringResource {
    switch self {
    case .pin: .loci("panels.pin")
    case .unpin: .loci("panels.unpin")
    case .note: .loci("panels.note")
    case .editNote: .loci("panels.editNote")
    case .take: .loci("panels.take")
    case .remove: .loci("panels.removeItem")
    }
  }
}

/// What right-clicking a line of a list in a panel offers.
enum PanelLineMenu: Equatable {
  case pin, unpin, note, editNote, hide

  static func entries(for mark: PanelLineMark) -> [PanelLineMenu] {
    [mark.pinned ? .unpin : .pin, mark.note == nil ? .note : .editNote, .hide]
  }

  var name: LocalizedStringResource {
    switch self {
    case .pin: .loci("panels.pin")
    case .unpin: .loci("panels.unpin")
    case .note: .loci("panels.note")
    case .editNote: .loci("panels.editNote")
    case .hide: .loci("panels.hide")
    }
  }
}

/// A list's lines with the person's take on each: hidden ones left out, pinned ones first.
struct MarkedLines {
  struct Line {
    let line: PanelListItem
    let mark: PanelLineMark
  }

  let shown: [Line]

  init(_ lines: [PanelListItem], marks: [PanelLineKey: PanelLineMark]) {
    let marked = lines.map { Line(line: $0, mark: marks[PanelLineKey($0)] ?? PanelLineMark()) }.filter {
      !$0.mark.hidden
    }
    shown = marked.filter(\.mark.pinned) + marked.filter { !$0.mark.pinned }
  }
}
