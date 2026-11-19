import AppKit
import SwiftUI

/// Three dots rising in turn in Loci's bubble while it has not said anything yet.
///
/// Core Animation moves them on its own, so waiting for Loci costs the app no work frame by frame and
/// nothing around the dots is drawn again.
struct TypingDots: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Dots(moving: !reduceMotion)
      .frame(width: Dots.width, height: Dots.size)
      .padding(.vertical, 5)
      .padding(.horizontal, 2)
      .accessibilityHidden(true)
  }
}

private struct Dots: NSViewRepresentable {
  let moving: Bool

  static let size: CGFloat = 6
  static let width = size * 3 + Spacing.xxs * 2

  func makeNSView(context: Context) -> DotsView { DotsView() }

  func updateNSView(_ view: DotsView, context: Context) {
    view.moving = moving
  }
}

private final class DotsView: NSView {
  /// Each dot rises and falls in the first half of a beat this long, then rests, a little after the one
  /// before it.
  private static let beat: CFTimeInterval = 1.2
  private static let lag: CFTimeInterval = 0.15
  private static let rise: CGFloat = 3

  private let dots = (0..<3).map { _ in CALayer() }

  var moving = true {
    didSet { if moving != oldValue { animate() } }
  }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    for dot in dots {
      dot.cornerRadius = Dots.size / 2
      dot.opacity = 0.5
      layer?.addSublayer(dot)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    var color: CGColor?
    effectiveAppearance.performAsCurrentDrawingAppearance { color = Tones.inkFaint.cgColor }
    for dot in dots { dot.backgroundColor = color }
  }

  override func layout() {
    super.layout()
    for (index, dot) in dots.enumerated() {
      dot.frame = CGRect(
        x: CGFloat(index) * (Dots.size + Spacing.xxs), y: 0, width: Dots.size, height: Dots.size)
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
      dot.add(Self.bounce(after: CFTimeInterval(index) * Self.lag), forKey: "bounce")
    }
  }

  private static func bounce(after delay: CFTimeInterval) -> CAAnimation {
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
