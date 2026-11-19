import AppKit
import SwiftUI

/// Three dots rising in turn in Loci's bubble while it has not said anything yet.
struct TypingDots: View {
  var body: some View {
    DotRow(size: 6, gap: Spacing.xxs, rise: 3, color: Tones.inkFaint)
      .padding(.vertical, 5)
      .padding(.horizontal, 2)
  }
}

/// Three dots that brighten one after another, rising as they do when `rise` is more than zero, as long as
/// the person has not asked for less motion.
///
/// Core Animation moves them on its own, so dots that go on for minutes cost the app no work frame by frame
/// and nothing around them is laid out again.
struct DotRow: View {
  let size: CGFloat
  let gap: CGFloat
  let rise: CGFloat
  let color: NSColor
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    DotLayers(size: size, gap: gap, rise: rise, color: color, moving: !reduceMotion)
      .frame(width: size * 3 + gap * 2, height: size)
      .accessibilityHidden(true)
  }
}

private struct DotLayers: NSViewRepresentable {
  let size: CGFloat
  let gap: CGFloat
  let rise: CGFloat
  let color: NSColor
  let moving: Bool

  func makeNSView(context: Context) -> DotsView { DotsView() }

  func updateNSView(_ view: DotsView, context: Context) {
    view.shape = DotsView.Shape(size: size, gap: gap, rise: rise)
    view.color = color
    view.moving = moving
  }
}

private final class DotsView: NSView {
  struct Shape: Equatable {
    let size: CGFloat
    let gap: CGFloat
    let rise: CGFloat
  }

  /// Each dot brightens in the first half of a beat this long, then rests, a little after the one before it.
  private static let beat: CFTimeInterval = 1.2
  private static let lag: CFTimeInterval = 0.15

  private let dots = (0..<3).map { _ in CALayer() }

  var shape = Shape(size: 0, gap: 0, rise: 0) {
    didSet {
      guard shape != oldValue else { return }
      needsLayout = true
      animate()
    }
  }

  var color = NSColor.clear {
    didSet { if color != oldValue { needsDisplay = true } }
  }

  var moving = true {
    didSet { if moving != oldValue { animate() } }
  }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    for dot in dots {
      dot.opacity = 0.5
      layer?.addSublayer(dot)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    var resolved: CGColor?
    effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
    for dot in dots { dot.backgroundColor = resolved }
  }

  override func layout() {
    super.layout()
    for (index, dot) in dots.enumerated() {
      dot.frame = CGRect(
        x: CGFloat(index) * (shape.size + shape.gap), y: 0, width: shape.size, height: shape.size)
      dot.cornerRadius = shape.size / 2
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    animate()
  }

  private func animate() {
    for (index, dot) in dots.enumerated() {
      dot.removeAllAnimations()
      guard moving, window != nil else { continue }
      dot.add(Self.beat(rising: shape.rise, after: CFTimeInterval(index) * Self.lag), forKey: "beat")
    }
  }

  private static func beat(rising rise: CGFloat, after delay: CFTimeInterval) -> CAAnimation {
    let times: [NSNumber] = [0, 0.25, 0.5, 1]
    let lift = CAKeyframeAnimation(keyPath: "transform.translation.y")
    lift.values = [0, rise, 0, 0]
    lift.keyTimes = times
    let fade = CAKeyframeAnimation(keyPath: "opacity")
    fade.values = [0.5, 1, 0.5, 0.5]
    fade.keyTimes = times
    let group = CAAnimationGroup()
    group.animations = [lift, fade]
    group.duration = beat
    group.repeatCount = .infinity
    group.timeOffset = beat - delay
    return group
  }
}
