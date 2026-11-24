import SwiftUI

/// Two sections of a page side by side, the second narrower, when the page is wide enough for both;
/// otherwise the second goes under the first.
struct PageColumns: Layout {
  var spacing: CGFloat = 28
  var stackedSpacing: CGFloat = 22
  /// The narrowest the first section may be beside the second.
  var narrowestFirst: CGFloat = 420
  var second: ClosedRange<CGFloat> = 260...380
  /// How much of the width the second section asks for, within `second`.
  var share: CGFloat = 0.38

  /// The width of each section at `width`, or `nil` when they go one under the other.
  func widths(for width: CGFloat) -> (first: CGFloat, second: CGFloat)? {
    let side = min(max(width * share, second.lowerBound), second.upperBound)
    let first = width - side - spacing
    return first >= narrowestFirst ? (first, side) : nil
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? narrowestFirst + spacing + second.upperBound
    let heights = place(in: width, subviews: subviews).map(\.size.height)
    guard widths(for: width) != nil else {
      return CGSize(width: width, height: heights.reduce(0, +) + stackedSpacing * CGFloat(max(0, heights.count - 1)))
    }
    return CGSize(width: width, height: heights.max() ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (subview, frame) in zip(subviews, place(in: bounds.width, subviews: subviews)) {
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
        proposal: ProposedViewSize(width: frame.width, height: nil))
    }
  }

  private func place(in width: CGFloat, subviews: Subviews) -> [CGRect] {
    if let (first, side) = widths(for: width) {
      return subviews.enumerated().map { index, subview in
        let wide = index == 0 ? first : side
        let height = subview.sizeThatFits(ProposedViewSize(width: wide, height: nil)).height
        return CGRect(x: index == 0 ? 0 : first + spacing, y: 0, width: wide, height: height)
      }
    }
    var y: CGFloat = 0
    return subviews.map { subview in
      let height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
      defer { y += height + stackedSpacing }
      return CGRect(x: 0, y: y, width: width, height: height)
    }
  }
}
