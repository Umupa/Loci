import SwiftUI

extension View {
  /// Rises into place as it fades in when it arrives, and simply appears for someone who asked for less
  /// motion.
  func arriving() -> some View {
    modifier(Arriving())
  }

  /// Animates what arrives as `value` changes, unless the person asked for less motion.
  func animatingArrivals(_ value: some Equatable) -> some View {
    modifier(AnimatingArrivals(value: value))
  }

  /// A card's soft shadow in light; in dark, where shadows vanish, a faint hairline instead.
  func cardShadow<S: InsettableShape>(_ shape: S) -> some View {
    modifier(CardShadow(shape: shape))
  }
}

private struct CardShadow<S: InsettableShape>: ViewModifier {
  let shape: S
  @Environment(\.colorScheme) private var scheme

  func body(content: Content) -> some View {
    if scheme == .dark {
      content.overlay(shape.strokeBorder(Palette.cardEdge, lineWidth: Size.hairline))
    } else {
      content
        .shadow(color: .black.opacity(0.04), radius: 0, y: 0.5)
        .shadow(color: Palette.warmShadow.opacity(0.08), radius: 1.5, y: 1)
    }
  }
}

private struct Arriving: ViewModifier {
  @Environment(\.reducesMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: Motion.riseDistance)))
  }
}

private struct AnimatingArrivals<Value: Equatable>: ViewModifier {
  let value: Value
  @Environment(\.reducesMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.animation(reduceMotion ? nil : Motion.arrive, value: value)
  }
}
