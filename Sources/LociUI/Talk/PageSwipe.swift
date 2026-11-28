import AppKit
import SwiftUI

/// Whether two fingers moving across the trackpad turn pages or scroll what is under them, decided once
/// they have moved far enough to tell.
enum SwipeClaim: Equatable {
  case claim
  case pass

  /// How far the fingers move before it is decided, in points.
  static let decidingDistance: CGFloat = 8
  /// How much more across than up or down a swipe must go to turn pages.
  static let dominance: CGFloat = 1.8

  /// `nil` while the fingers have not moved far enough to tell.
  static func decide(dx: CGFloat, dy: CGFloat) -> SwipeClaim? {
    guard hypot(dx, dy) >= decidingDistance else { return nil }
    return abs(dx) > abs(dy) * dominance ? .claim : .pass
  }
}

/// What a swipe across the companion's page tells it: the fingers have taken the page, how far they have
/// moved it since, and how far and how fast it was let go; `nil` speed when the system called it off.
struct PageSwipeActions {
  let began: () -> Void
  let moved: (CGFloat) -> Void
  let ended: (_ offset: CGFloat, _ velocity: CGFloat?) -> Void
}

/// Watches two-finger swipes across the trackpad over the area it covers, and takes those mostly across, with
/// the momentum after them; the rest, and the mouse wheel, scroll as they always did.
struct PageSwipe: NSViewRepresentable {
  let enabled: Bool
  let actions: PageSwipeActions

  func makeNSView(context: Context) -> SwipeArea { SwipeArea() }

  func updateNSView(_ area: SwipeArea, context: Context) {
    area.enabled = enabled
    area.actions = actions
  }

  static func dismantleNSView(_ area: SwipeArea, coordinator: ()) { area.stop() }
}

/// One two-finger gesture on the trackpad, step by step: whether each step is taken from what is under the
/// fingers, and what the page is told. Once taken, the gesture's momentum is taken too; once left alone, all
/// of it is.
struct SwipeTracker {
  enum Step: Equatable {
    case began
    case changed
    case ended
    case cancelled
    /// The gesture coasting on after the fingers lifted; `last` for its final step.
    case momentum(last: Bool)
  }

  enum Told: Equatable {
    case began
    case moved(CGFloat)
    case ended(CGFloat, velocity: CGFloat?)
  }

  private var dx: CGFloat = 0
  private var dy: CGFloat = 0
  private var claim: SwipeClaim?
  private var watching = false
  private var released = false
  private var samples: [(time: TimeInterval, dx: CGFloat)] = []

  /// Takes `step`, moving `dx` across in the fingers' direction and `dy` up or down at `time`. A gesture is
  /// watched only when it begins `inside` the pages while swipes may turn them; `scrollsAcross` says whether
  /// what is under the fingers scrolls sideways itself.
  mutating func take(
    _ step: Step, dx: CGFloat, dy: CGFloat, at time: TimeInterval, inside: Bool, scrollsAcross: () -> Bool
  ) -> (taken: Bool, told: [Told]) {
    switch step {
    case .momentum(let last):
      let taken = claim == .claim && released
      if last || !taken { reset() }
      return (taken, [])
    case .began:
      reset()
      watching = inside
      if watching { add(dx: dx, dy: dy, at: time) }
      return (false, [])
    case .changed, .ended, .cancelled:
      guard watching, !released else { return (false, []) }
      let over = step != .changed
      switch claim {
      case nil:
        add(dx: dx, dy: dy, at: time)
        claim = SwipeClaim.decide(dx: self.dx, dy: self.dy)
        if claim == .claim, scrollsAcross() { claim = .pass }
        let taken = claim == .claim && !over
        if over { reset() }
        return taken ? (true, [.began, .moved(self.dx)]) : (false, [])
      case .pass:
        if over { reset() }
        return (false, [])
      case .claim:
        if over {
          released = true
          return (true, [.ended(self.dx, velocity: step == .cancelled ? nil : velocity)])
        }
        add(dx: dx, dy: dy, at: time)
        return (true, [.moved(self.dx)])
      }
    }
  }

  private mutating func add(dx: CGFloat, dy: CGFloat, at time: TimeInterval) {
    self.dx += dx
    self.dy += dy
    samples.append((time, self.dx))
    samples.removeAll { $0.time < time - 0.1 }
  }

  private mutating func reset() { self = SwipeTracker() }

  /// Points a second over the last moments before the fingers lifted.
  private var velocity: CGFloat {
    guard let first = samples.first, let last = samples.last, last.time - first.time > 0.008 else { return 0 }
    return (last.dx - first.dx) / CGFloat(last.time - first.time)
  }
}

final class SwipeArea: NSView {
  var enabled = false
  var actions: PageSwipeActions?
  private var monitor: Any?
  private var tracker = SwipeTracker()

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    stop()
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      self?.handle(event) ?? event
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    tracker = SwipeTracker()
  }

  /// Takes a scroll the tracker takes, and tells the page what it told.
  func handle(_ event: NSEvent) -> NSEvent? {
    guard event.window === window, event.hasPreciseScrollingDeltas, let step = Self.step(of: event) else {
      return event
    }
    let across = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
    let taken = take(
      step, across: across, upward: event.scrollingDeltaY, at: event.timestamp, in: event.locationInWindow)
    return taken ? nil : event
  }

  /// Takes one step of a gesture at `location` in the window, the fingers moving `across` and `upward`; whether
  /// it is taken from what is under them.
  func take(_ step: SwipeTracker.Step, across: CGFloat, upward: CGFloat, at time: TimeInterval, in location: CGPoint)
    -> Bool
  {
    let inside = enabled && !isHiddenOrHasHiddenAncestor && bounds.contains(convert(location, from: nil))
    let (taken, told) = tracker.take(
      step, dx: across, dy: upward, at: time, inside: inside, scrollsAcross: { self.scrollsAcross(at: location) })
    for each in told {
      switch each {
      case .began: actions?.began()
      case .moved(let offset): actions?.moved(offset)
      case .ended(let offset, let velocity): actions?.ended(offset, velocity)
      }
    }
    return taken
  }

  private static func step(of event: NSEvent) -> SwipeTracker.Step? {
    if !event.momentumPhase.isEmpty {
      return .momentum(last: event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled))
    }
    if event.phase.contains(.began) { return .began }
    if event.phase.contains(.changed) { return .changed }
    if event.phase.contains(.ended) { return .ended }
    if event.phase.contains(.cancelled) { return .cancelled }
    return nil
  }

  /// Whether what is under the fingers scrolls across by itself, such as a wide table or a web page.
  private func scrollsAcross(at location: CGPoint) -> Bool {
    guard let content = window?.contentView else { return false }
    var view = content.hitTest(content.superview?.convert(location, from: nil) ?? .zero)
    while let shown = view {
      if let scroll = shown as? NSScrollView, let document = scroll.documentView,
        document.frame.width > scroll.contentSize.width + 1
      {
        return true
      }
      if shown.className.hasPrefix("WK") { return true }
      view = shown.superview
    }
    return false
  }
}
