import AppKit
import SwiftUI

/// A round dot that fades to `Motion.breathLow` and back once every `period` seconds while `breathing`, as
/// long as the person has not asked for less motion: Loci's dot while it works, the step of a task going on
/// now.
///
/// Core Animation runs the breath on its own, so a dot breathing for minutes costs the app no work frame by
/// frame, and one that stops has nothing left running.
struct BreathingDot: View {
  let color: NSColor
  let size: CGFloat
  let breathing: Bool
  let period: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    DotLayer(color: color, breath: breathing && !reduceMotion ? period : nil)
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

private struct DotLayer: NSViewRepresentable {
  let color: NSColor
  let breath: Double?

  func makeNSView(context: Context) -> DotView { DotView() }

  func updateNSView(_ view: DotView, context: Context) {
    view.color = color
    view.breath = breath
  }
}

private final class DotView: NSView {
  private let dot = CALayer()

  var color = NSColor.clear {
    didSet { if color != oldValue { needsDisplay = true } }
  }

  var breath: Double? {
    didSet { if breath != oldValue { animate() } }
  }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.addSublayer(dot)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    var resolved: CGColor?
    effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
    dot.backgroundColor = resolved
  }

  override func layout() {
    super.layout()
    dot.frame = bounds
    dot.cornerRadius = min(bounds.width, bounds.height) / 2
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    animate()
  }

  private func animate() {
    dot.removeAllAnimations()
    guard let breath, window != nil else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1
    fade.toValue = Motion.breathLow
    fade.duration = breath / 2
    fade.autoreverses = true
    fade.repeatCount = .infinity
    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    dot.add(fade, forKey: "breath")
  }
}
