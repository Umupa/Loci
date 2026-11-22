import SwiftUI

/// The paragraphs of a page being written coming into view one at a time, however many arrive together: each a
/// beat after the one before it, or as soon as it arrives when that is later.
struct ParagraphPace: Equatable {
  static let beat = Duration.milliseconds(650)

  /// The page the paragraphs are on.
  let number: Int
  /// When each paragraph comes into view.
  private(set) var due: [ContinuousClock.Instant]
  /// How many are in view.
  private(set) var shown: Int

  /// A page with `shown` paragraphs in view from the start.
  init(number: Int, showing shown: Int, at now: ContinuousClock.Instant) {
    self.number = number
    due = Array(repeating: now, count: shown)
    self.shown = shown
  }

  /// When the next paragraph not yet in view comes into view.
  var next: ContinuousClock.Instant? {
    shown < due.count ? due[shown] : nil
  }

  /// The page now has `total` paragraphs.
  mutating func arrived(_ total: Int, at now: ContinuousClock.Instant) {
    if total < due.count {
      due.removeLast(due.count - total)
      shown = min(shown, total)
    }
    while due.count < total {
      due.append(max(now, due.last.map { $0 + Self.beat } ?? now))
    }
  }

  /// Brings into view every paragraph due by `now`.
  mutating func catchUp(at now: ContinuousClock.Instant) {
    while shown < due.count, due[shown] <= now { shown += 1 }
  }
}

/// Paragraphs down a page of fixed height: from the top while they fit, and once they no longer do, the last
/// one sits at the foot and the earlier ones run up past the top, under the view marked `fadesOverflow()` laid
/// along the top edge.
struct LatestLines: Layout {
  var spacing: CGFloat
  /// How tall the view along the top edge is once the paragraphs no longer fit.
  var fade: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 0
    if let height = proposal.height, height.isFinite { return CGSize(width: width, height: height) }
    return CGSize(width: width, height: total(heights(subviews.filter { !$0[Fade.self] }, width: width)))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let paragraphs = subviews.filter { !$0[Fade.self] }
    let heights = heights(paragraphs, width: bounds.width)
    let overflow = max(0, total(heights) - bounds.height)
    var top = bounds.minY - overflow
    for (subview, height) in zip(paragraphs, heights) {
      subview.place(
        at: CGPoint(x: bounds.minX, y: top), proposal: ProposedViewSize(width: bounds.width, height: height))
      top += height + spacing
    }
    for veil in subviews where veil[Fade.self] {
      veil.place(
        at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: overflow > 0 ? fade : 0))
    }
  }

  private func total(_ heights: [CGFloat]) -> CGFloat {
    heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
  }

  private func heights(_ subviews: some Collection<LayoutSubview>, width: CGFloat) -> [CGFloat] {
    subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
  }

  fileprivate struct Fade: LayoutValueKey {
    static let defaultValue = false
  }
}

extension View {
  /// Marks the view laid along the top of `LatestLines` once its paragraphs run past the top.
  func fadesOverflow() -> some View {
    layoutValue(key: LatestLines.Fade.self, value: true)
  }
}
