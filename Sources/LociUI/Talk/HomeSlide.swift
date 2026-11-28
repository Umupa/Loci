import LociModel
import SwiftUI

/// A page the companion's page turns between: a home, or a new project's page right of them all.
enum SlidePage: Hashable {
  case home(Home)
  case newProject

  var home: Home? {
    if case .home(let home) = self { home } else { nil }
  }
}

/// Which way a page lies from the one in front.
enum Side: Equatable {
  case left
  case right

  var step: Double { self == .right ? 1 : -1 }
}

/// How the companion's pages lie side by side, in the project bar's order, and when a swipe turns them.
enum HomeSlide {
  /// How far ahead a swipe's speed carries it when let go, in seconds.
  static let carry: CGFloat = 0.15
  /// How fast a swipe let go toward a page turns to it however short it was, in points a second.
  static let flick: CGFloat = 300

  /// The chat, then the projects in the bar and in its list, then the archived ones.
  static func order(of bar: ProjectBar) -> [Home] {
    [.chat] + (bar.projects + bar.archived).map { .project($0.id) }
  }

  /// Which side `to` comes in from; `nil` when it is already in front. A page no longer in the bar, such as a
  /// project just deleted, lies right of the others.
  static func side(from: SlidePage, to: SlidePage, in order: [Home]) -> Side? {
    let start = place(of: from, in: order)
    let end = place(of: to, in: order)
    return start == end ? nil : end > start ? .right : .left
  }

  /// The home beside `home` on `side`, to swipe to; `nil` past either end. A new project's page is never one.
  static func neighbour(of home: Home, on side: Side, in order: [Home]) -> Home? {
    guard let index = order.firstIndex(of: home) else { return nil }
    let next = index + Int(side.step)
    return order.indices.contains(next) ? order[next] : nil
  }

  /// Which side a swipe let go with `offset` and `velocity` turns to: flicked toward it, or carried past half a
  /// page at its speed. `nil` when it springs back: short and slow, or flung back the other way.
  static func outcome(offset: CGFloat, velocity: CGFloat, width: CGFloat) -> Side? {
    guard offset != 0, velocity.sign == offset.sign || abs(velocity) < flick else { return nil }
    let projected = offset + velocity * carry
    guard abs(velocity) >= flick || abs(projected) >= width / 2 else { return nil }
    return offset < 0 ? .right : .left
  }

  /// Where the project bar's slider is while two fingers `pull` the page in front toward the one beside it: part
  /// of the way from the `open` tab to that one's, or on the open tab when there is none beside it in the bar.
  static func slider(over tabs: [SlidePage: CGRect], open: SlidePage, pull: Double, in order: [Home]) -> CGRect? {
    guard let from = tabs[open] else { return nil }
    guard let home = open.home, pull != 0,
      let next = neighbour(of: home, on: pull > 0 ? .right : .left, in: order), let to = tabs[.home(next)]
    else { return from }
    let part = CGFloat(min(abs(pull), 1))
    return CGRect(
      x: from.minX + (to.minX - from.minX) * part, y: from.minY + (to.minY - from.minY) * part,
      width: from.width + (to.width - from.width) * part, height: from.height + (to.height - from.height) * part)
  }

  /// How far the page goes for a drag of `offset` past an end: less and less, never half a page.
  static func resisted(_ offset: CGFloat, width: CGFloat) -> CGFloat {
    let reach = width / 2
    let given = (1 - 1 / (abs(offset) * 0.55 / reach + 1)) * reach
    return offset < 0 ? -given : given
  }

  private static func place(of page: SlidePage, in order: [Home]) -> Int {
    switch page {
    case .home(let home): order.firstIndex(of: home) ?? order.count
    case .newProject: order.count + 1
    }
  }
}

/// The pages on screen side by side, each at its slot along a strip, in pages. The strip slides by a position
/// kept apart from it; the page in front is there once the slide is over. Turning again before then is just a
/// new place to slide to, so taps never queue.
struct PageStrip: Equatable {
  private(set) var front: SlidePage
  /// Only the pages on screen have a slot.
  private var slots: [SlidePage: Double]

  init(front: SlidePage) {
    self.front = front
    slots = [front: 0]
  }

  /// The pages on screen, left to right.
  var onScreen: [SlidePage] { slots.sorted { $0.value < $1.value }.map(\.key) }

  /// Where the strip is when the page in front is.
  var frontPosition: Double { slots[front] ?? 0 }

  func slot(of page: SlidePage) -> Double? { slots[page] }

  /// Where `page` is drawn across a page `width` wide while the strip is at `position`; `nil` off screen.
  func x(of page: SlidePage, position: Double, width: CGFloat) -> CGFloat? {
    Self.x(slot: slots[page], position: position, width: width)
  }

  static func x(slot: Double?, position: Double, width: CGFloat) -> CGFloat? {
    slot.map { CGFloat($0 - position) * width }
  }

  /// Where the strip is while fingers have moved the page in front by `offset` points.
  func position(dragged offset: CGFloat, width: CGFloat) -> Double {
    width > 0 ? frontPosition - Double(offset / width) : frontPosition
  }

  /// Puts `page` in front, brought in on `side` of the strip shown at `position`, for the strip to slide to.
  mutating func turn(to page: SlidePage, on side: Side, from position: Double) {
    bring(page, on: side, from: position)
    front = page
  }

  /// Sets the pages beside the one in front, for a swipe to show as it drags.
  mutating func peek(left: SlidePage?, right: SlidePage?, from position: Double) {
    if let left { bring(left, on: .left, from: position) }
    if let right { bring(right, on: .right, from: position) }
  }

  /// Puts `page` on screen beside the page in front on `side`, unless it is already on screen. A page still
  /// showing while the strip is at `position` keeps its slot, and `page` goes past it; one out of sight gives
  /// its slot up.
  mutating func bring(_ page: SlidePage, on side: Side, from position: Double) {
    guard slots[page] == nil else { return }
    var slot = frontPosition + side.step
    while slots.contains(where: { $0.value == slot && ($0.key == front || abs(slot - position) < 1) }) {
      slot += side.step
    }
    slots = slots.filter { $0.value != slot }
    slots[page] = slot
  }

  /// `page` takes the place of the page in front, where it is, without sliding.
  mutating func hand(to page: SlidePage) {
    let slot = frontPosition
    slots[front] = nil
    slots[page] = slot
    front = page
  }

  /// The slide is over: only the page in front stays on screen, at the start of the strip.
  mutating func settle() {
    slots = [front: 0]
  }
}

/// A slide of the strip from `from` to `to`, setting off at `speed` pages a second: where it is at any moment,
/// so a swipe or a turn begun before it ends takes the strip from where it is shown.
struct PageFlight {
  let from: Double
  let to: Double
  let speed: Double
  let start: ContinuousClock.Instant

  /// The slide, carrying on at `speed` as it sets off.
  var animation: Animation { .interpolatingSpring(Motion.pageSpring, initialVelocity: relativeSpeed) }

  func position(at now: ContinuousClock.Instant) -> Double {
    let elapsed = now - start
    let time = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    return from + (to - from) * Motion.pageSpring.value(target: 1.0, initialVelocity: relativeSpeed, time: time)
  }

  /// The speed as a share of the way to go each second, as springs take it.
  private var relativeSpeed: Double {
    abs(to - from) < 0.001 ? 0 : max(-20, min(20, speed / (to - from)))
  }
}

/// Draws a page at its `slot` as the strip slides; only the strip's position animates, so a page given a new
/// slot is there at once. The page moves only where it is drawn, not where it is laid out, so nothing in it that
/// measures itself is asked again on every frame of a slide.
struct StripPlace: ViewModifier, Animatable {
  var position: Double
  let slot: Double?
  let width: CGFloat

  nonisolated var animatableData: Double {
    get { position }
    set { position = newValue }
  }

  func body(content: Content) -> some View {
    let x = PageStrip.x(slot: slot, position: position, width: width)
    content
      .visualEffect { page, _ in page.offset(x: x ?? 0) }
      .opacity(x == nil ? 0 : 1)
  }
}
