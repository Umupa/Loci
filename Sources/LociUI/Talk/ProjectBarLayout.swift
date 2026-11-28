import AppKit
import LociModel
import SwiftUI

/// Which projects stay on the top bar at the current width, how wide the active project's name may spread,
/// and which overflow projects fold into the list.
struct ProjectBarPlan: Equatable {
  let visible: [Project]
  let hidden: [Project]
  let openNameWidth: CGFloat

  var overflowCount: Int { hidden.count }

  static let tabHeight: CGFloat = 30
  static let sealTabWidth: CGFloat = 28
  static let spacing: CGFloat = 2
  static let outerPadding: CGFloat = 4
  static let dividerWidth: CGFloat = Size.hairline + 8
  static let openLabelPadding: CGFloat = 12
  static let addButtonWidth: CGFloat = 28
  static let unfoldButtonWidth: CGFloat = 28
  static let overflowUnfoldPadding: CGFloat = 30

  static func compute(
    projects: [Project], home: Home, drafting: Bool, availableWidth: CGFloat, chatLabel: String
  ) -> ProjectBarPlan {
    let budget = max(240, min(Size.projectBarWidest, availableWidth))
    let chatWidth = ceil(labelWidth(chatLabel, weight: .semibold)) + 20

    func width(projectSlots: Int, openExtra: CGFloat, overflow: Int) -> CGFloat {
      let unfold = overflow > 0 ? overflowWidth(count: overflow) : unfoldButtonWidth
      let dividers = projectSlots > 0 ? 2 : 1
      let itemCount = 3 + dividers + projectSlots
      let middle = CGFloat(projectSlots) * sealTabWidth + openExtra
      let gaps = CGFloat(max(0, itemCount - 1)) * spacing
      return outerPadding * 2 + chatWidth + dividerWidth * CGFloat(dividers) + middle + addButtonWidth + unfold + gaps
    }

    if drafting {
      let kept = fittingCount(total: projects.count) { count, overflow in
        width(projectSlots: count + 1, openExtra: 0, overflow: overflow) <= budget
      }
      return ProjectBarPlan(
        visible: Array(projects.prefix(kept)), hidden: Array(projects.dropFirst(kept)), openNameWidth: 0)
    }

    if case .project(let activeID) = home, let activeIndex = projects.firstIndex(where: { $0.id == activeID }) {
      let active = projects[activeIndex]
      guard let name = active.name else {
        let kept = fittingCount(total: projects.count) { count, overflow in
          width(projectSlots: count, openExtra: 0, overflow: overflow) <= budget
        }
        let visible =
          activeIndex < kept ? Array(projects.prefix(kept)) : Array(projects.prefix(max(0, kept - 1))) + [active]
        let shown = Set(visible.map(\.id))
        return ProjectBarPlan(visible: visible, hidden: projects.filter { !shown.contains($0.id) }, openNameWidth: 0)
      }
      let natural = min(Size.projectNameWidest, ceil(labelWidth(name, weight: .semibold)))
      let fullExtra = natural + openLabelPadding
      if width(projectSlots: projects.count, openExtra: fullExtra, overflow: 0) <= budget {
        return ProjectBarPlan(visible: projects, hidden: [], openNameWidth: natural)
      }

      let floorName = min(natural, Size.projectNameNarrow)
      if width(projectSlots: projects.count, openExtra: floorName + openLabelPadding, overflow: 0) <= budget {
        let baseWithoutName = width(projectSlots: projects.count, openExtra: openLabelPadding, overflow: 0)
        let elastic = min(natural, max(floorName, budget - baseWithoutName))
        return ProjectBarPlan(visible: projects, hidden: [], openNameWidth: elastic)
      }

      let kept = max(
        1,
        fittingCount(total: projects.count) { count, overflow in
          width(projectSlots: count, openExtra: floorName + openLabelPadding, overflow: overflow) <= budget
        })
      let visible: [Project] =
        activeIndex < kept
        ? Array(projects.prefix(kept))
        : Array(projects.prefix(max(0, kept - 1))) + [active]
      let visibleIDs = Set(visible.map(\.id))
      let hidden = projects.filter { !visibleIDs.contains($0.id) }
      let baseWithoutName = width(projectSlots: visible.count, openExtra: openLabelPadding, overflow: hidden.count)
      let nameWidth = min(natural, max(floorName, budget - baseWithoutName))
      return ProjectBarPlan(visible: visible, hidden: hidden, openNameWidth: nameWidth)
    }

    let kept = fittingCount(total: projects.count) { count, overflow in
      width(projectSlots: count, openExtra: 0, overflow: overflow) <= budget
    }
    return ProjectBarPlan(
      visible: Array(projects.prefix(kept)), hidden: Array(projects.dropFirst(kept)), openNameWidth: 0)
  }

  private static func fittingCount(total: Int, fits: (Int, Int) -> Bool) -> Int {
    guard total > 0 else { return 0 }
    for count in stride(from: total, through: 0, by: -1) {
      if fits(count, total - count) { return count }
    }
    return 0
  }

  private static func overflowWidth(count: Int) -> CGFloat {
    ceil(labelWidth("+\(count)", weight: .semibold, size: 11)) + overflowUnfoldPadding
  }

  private static func labelWidth(_ text: String, weight: NSFont.Weight, size: CGFloat = 13.5) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    return (text as NSString).size(withAttributes: [.font: font]).width
  }
}

/// Smoothly reveals or hides a tab's name in place without re-wrapping or scaling glyphs mid-flight.
struct RevealWidth: Layout, Animatable {
  var fraction: CGFloat
  let maxWidth: CGFloat

  var animatableData: CGFloat {
    get { fraction }
    set { fraction = newValue }
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let child = subviews.first else { return .zero }
    let target = child.sizeThatFits(ProposedViewSize(width: maxWidth, height: proposal.height))
    return CGSize(width: target.width * fraction, height: target.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard let child = subviews.first else { return }
    let target = child.sizeThatFits(ProposedViewSize(width: maxWidth, height: bounds.height))
    child.place(at: bounds.origin, proposal: ProposedViewSize(width: target.width, height: bounds.height))
  }
}

/// Centres the project bar while there is room, and uses open space on the leading side before squeezing it.
struct BarClearance: Layout {
  let leading: CGFloat
  let trailing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let bar = subviews.first else { return .zero }
    let available = proposal.width.map { max(0, $0 - leading - trailing) }
    let size = bar.sizeThatFits(ProposedViewSize(width: available, height: proposal.height))
    return CGSize(width: proposal.width ?? (size.width + leading + trailing), height: size.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard let bar = subviews.first else { return }
    let available = max(0, bounds.width - leading - trailing)
    let fit = bar.sizeThatFits(ProposedViewSize(width: available, height: proposal.height))
    let minX = bounds.minX + leading
    let maxX = max(minX, bounds.maxX - trailing - fit.width)
    let centered = bounds.minX + (bounds.width - fit.width) / 2
    let x = min(max(centered, minX), maxX)
    bar.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(fit))
  }
}
