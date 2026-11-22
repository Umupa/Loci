import SwiftUI

/// Cards that came one after another. One is a card on its own. Two or more lie in a stack, the first
/// whole on top and the next ones showing their edges, turned a little; clicking the stack spreads it
/// into a grid of two columns in place, the first card first, and clicking anywhere but on a card gathers it
/// again.
struct CardStack<Element, Card: View>: View {
  let cards: [Element]
  /// A card, and whether its words show: they do on top of a stack and in the grid.
  let card: (Element, _ showsWords: Bool) -> Card
  let open: (Element) -> Void
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var spread: Bool
  @State private var watcher = StackSpread()
  @Environment(\.conversationCover) private var cover

  /// `spread` starts it out as a grid.
  init(
    cards: [Element], spread: Bool = false, @ViewBuilder card: @escaping (Element, _ showsWords: Bool) -> Card,
    open: @escaping (Element) -> Void
  ) {
    self.cards = cards
    _spread = State(initialValue: spread)
    self.card = card
    self.open = open
  }

  var body: some View {
    let layout = spread ? AnyLayout(TwoColumns(spacing: 16)) : AnyLayout(Pile(width: CardShell<EmptyView>.width))
    layout {
      ForEach(cards.indices, id: \.self) { index in
        let element = cards[index]
        Button {
          if spread || cards.count == 1 { open(element) } else { setSpread(true) }
        } label: {
          card(element, spread || index == 0)
        }
        .buttonStyle(PressStyle())
        .rotationEffect(spread ? .zero : Self.turn(index))
        .offset(spread ? .zero : Self.shift(index))
        .opacity(spread || index < 3 ? 1 : 0)
        .zIndex(Double(cards.count - index))
        .onGeometryChange(for: CGRect.self) {
          $0.frame(in: .global)
        } action: {
          watcher.cards[index] = $0
        }
      }
    }
    .padding(.vertical, spread || cards.count == 1 ? 0 : 10)
    .padding(.leading, spread || cards.count == 1 ? 0 : 6)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .onChange(of: spread, initial: true) { _, spread in
      if spread { watcher.watch(covered: cover) { setSpread(false) } } else { watcher.stop() }
    }
    .onDisappear { watcher.stop() }
  }

  private func setSpread(_ open: Bool) {
    withAnimation(reduceMotion ? nil : Self.spring) { spread = open }
  }

  static var spring: Animation { .spring(duration: 0.55, bounce: 0.22) }

  /// The second card leans left and the third right, so both show an edge.
  static func turn(_ index: Int) -> Angle {
    switch index {
    case 1: .degrees(-5)
    case 2: .degrees(4)
    default: .zero
    }
  }

  static func shift(_ index: Int) -> CGSize {
    switch index {
    case 1: CGSize(width: -8, height: 4)
    case 2: CGSize(width: 8, height: 2)
    default: .zero
    }
  }
}

/// Every card at one width, one on top of another, as tall as the first.
private struct Pile: Layout {
  let width: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let first = subviews.first else { return .zero }
    return CGSize(width: width, height: first.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      subview.place(at: bounds.origin, proposal: ProposedViewSize(width: width, height: nil))
    }
  }
}

/// Two columns as wide as they can be, rows as tall as their taller card.
private struct TwoColumns: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? CardShell<EmptyView>.width * 2 + spacing
    let heights = rowHeights(subviews, column: column(width))
    return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0)))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let column = column(bounds.width)
    let heights = rowHeights(subviews, column: column)
    var y = bounds.minY
    for (row, height) in heights.enumerated() {
      for side in 0..<2 where row * 2 + side < subviews.count {
        let x = bounds.minX + CGFloat(side) * (column + spacing)
        subviews[row * 2 + side].place(
          at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: column, height: nil))
      }
      y += height + spacing
    }
  }

  private func column(_ width: CGFloat) -> CGFloat {
    (width - spacing) / 2
  }

  private func rowHeights(_ subviews: Subviews, column: CGFloat) -> [CGFloat] {
    stride(from: 0, to: subviews.count, by: 2).map { start in
      subviews[start..<min(start + 2, subviews.count)].map {
        $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height
      }.max() ?? 0
    }
  }
}
