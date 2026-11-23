import LociModel
import SwiftUI

/// An item being dragged within its panel: where it was grabbed, where the pointer is, and where it would
/// land. Where it lands is told from where the rows were when the drag started, so the rows making way for it
/// do not move the place it lands. While it lasts, the panel listens to the keyboard and the mouse button:
/// Escape calls it off, and so does a button that stays up without the drag having ended.
@MainActor
@Observable
final class ItemCarry {
  struct Carried {
    let item: PanelItem
    let checks: Bool
    /// Where the pointer went down; the drag is known by it.
    let start: CGPoint
    let grab: CGSize
    let size: CGSize
    var location: CGPoint
    var target: Target?
  }

  /// Before the `index`th item still to do in the section, or after the last.
  struct Target: Equatable {
    let section: String
    let index: Int
  }

  /// Where a drag that ended lands.
  struct Landing: Equatable {
    let item: PanelItem
    let target: Target
  }

  /// How many listens in a row the button may be up before a drag whose end never came is called off; the end
  /// of a drag let go normally comes well before.
  static let releaseGrace = 8

  private struct Row {
    let section: String
    let frame: CGRect
  }

  private(set) var carried: Carried?
  @ObservationIgnored private var rows: [String: Row] = [:]
  @ObservationIgnored private var sections: [String: CGRect] = [:]
  @ObservationIgnored private var start: (rows: [String: Row], sections: [String: CGRect])?
  /// Where the drag that was called off started; the rest of that drag is ignored, and a new one clears it.
  @ObservationIgnored private var calledOff: CGPoint?
  @ObservationIgnored private var upFor = 0

  func report(row id: String, in section: String, at frame: CGRect) {
    rows[id] = Row(section: section, frame: frame)
  }

  func report(section id: String, at frame: CGRect) {
    sections[id] = frame
  }

  func move(_ item: PanelItem, checks: Bool, from startLocation: CGPoint, to location: CGPoint) {
    if let calledOff {
      guard calledOff != startLocation else { return }
      self.calledOff = nil
    }
    if carried == nil {
      guard let frame = rows[item.id]?.frame else { return }
      start = (rows, sections)
      upFor = 0
      carried = Carried(
        item: item, checks: checks, start: startLocation,
        grab: CGSize(width: startLocation.x - frame.minX, height: startLocation.y - frame.minY), size: frame.size,
        location: location)
    }
    carried?.location = location
    let target = self.target(of: item.id, at: location.y)
    if target != carried?.target { carried?.target = target }
  }

  /// Where the item lands, unless the drag was called off. Either way nothing of the drag is left.
  func end() -> Landing? {
    defer {
      carried = nil
      start = nil
      calledOff = nil
    }
    guard let carried, let target = carried.target else { return nil }
    return Landing(item: carried.item, target: target)
  }

  /// Puts everything back as it was before the drag; what is left of it is ignored.
  func callOff() {
    guard let carried else { return }
    calledOff = carried.start
    self.carried = nil
    start = nil
  }

  /// Told every `Board.listening` while an item is carried, whether Escape and the mouse button are down.
  func listen(escape: Bool, buttonDown: Bool) {
    guard carried != nil else { return }
    upFor = buttonDown ? 0 : upFor + 1
    if escape || upFor >= Self.releaseGrace { callOff() }
  }

  private func target(of id: String, at y: CGFloat) -> Target? {
    guard let start else { return nil }
    let section =
      start.sections.first { $0.value.minY - 8 <= y && y <= $0.value.maxY + 8 }?.key
      ?? start.sections.min { distance($0.value, y) < distance($1.value, y) }?.key
    guard let section else { return nil }
    let frames = start.rows.filter { $0.key != id && $0.value.section == section }.map(\.value.frame)
      .sorted { $0.minY < $1.minY }
    return Target(section: section, index: ItemDrop.index(at: y, among: frames))
  }

  private func distance(_ frame: CGRect, _ y: CGFloat) -> CGFloat {
    y < frame.minY ? frame.minY - y : max(y - frame.maxY, 0)
  }
}

/// The dragged item, floating over the panel and tilted a little; where it was, an amber hollow waits.
struct CarriedItem: View {
  let carry: ItemCarry
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    if let carried = carry.carried {
      let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
      PanelItemRow(item: carried.item, checks: carried.checks)
        .frame(width: carried.size.width)
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
        .shadow(color: Palette.liftShadow, radius: 18, y: 10)
        .rotationEffect(.degrees(reduceMotion ? 0 : 1.2))
        .scaleEffect(reduceMotion ? 1 : 1.02)
        .offset(x: carried.location.x - carried.grab.width, y: carried.location.y - carried.grab.height)
        .allowsHitTesting(false)
    }
  }
}

/// Where a dragged item would land: its height, ringed in amber.
struct ItemHollow: View {
  let height: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
    shape.fill(Palette.tint).overlay(shape.strokeBorder(Palette.accentLine, lineWidth: 1.5)).frame(height: height)
  }
}

extension EnvironmentValues {
  /// Set by a panel whose items can be dragged.
  @Entry var itemCarry: ItemCarry?
}
