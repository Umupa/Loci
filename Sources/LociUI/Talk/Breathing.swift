import SwiftUI

extension View {
  /// Fades to `Motion.breathLow` and back while `on`, as long as the person has not asked for less motion.
  func breathing(_ on: Bool, period: Double) -> some View {
    modifier(Breathing(on: on, period: period))
  }

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

/// While it breathes, the content sits in a branch of its own, so when it stops the branch goes and its
/// repeating animation with it.
private struct Breathing: ViewModifier {
  let on: Bool
  let period: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if on && !reduceMotion {
      content.phaseAnimator([1, Motion.breathLow]) { content, opacity in
        content.opacity(opacity)
      } animation: { _ in
        Motion.breath(period)
      }
    } else {
      content
    }
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: Motion.riseDistance)))
  }
}

private struct AnimatingArrivals<Value: Equatable>: ViewModifier {
  let value: Value
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.animation(reduceMotion ? nil : Motion.arrive, value: value)
  }
}
