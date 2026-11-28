import LociModel
import SwiftUI

/// A page the companion's page turns between: a home, or a new project's page right of them all.
enum SlidePage: Hashable {
  case home(Home)
  case newProject
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

  /// Which side a swipe let go with `offset` and `velocity` turns to, carrying on at its speed a little; `nil`
  /// when it springs back: short of half a page, or flung back the other way.
  static func outcome(offset: CGFloat, velocity: CGFloat, width: CGFloat) -> Side? {
    let projected = offset + velocity * carry
    guard abs(projected) >= width / 2, projected.sign == offset.sign, offset != 0 else { return nil }
    return offset < 0 ? .right : .left
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

/// The pages on screen side by side, each at its slot along a strip that slides by `position`, in pages.
/// The page in front is at `position` once the slide is over; turning again before it is just a new place to
/// slide to, so taps never queue.
struct PageStrip: Equatable {
  private(set) var front: SlidePage
  private(set) var position: Double = 0
  /// Only the pages on screen have a slot.
  private var slots: [SlidePage: Double]

  init(front: SlidePage) {
    self.front = front
    slots = [front: 0]
  }

  /// The pages on screen, left to right.
  var onScreen: [SlidePage] { slots.sorted { $0.value < $1.value }.map(\.key) }

  /// Where `page` is drawn across a page `width` wide while the strip is at `position`; `nil` off screen.
  func x(of page: SlidePage, position: Double, width: CGFloat) -> CGFloat? {
    slots[page].map { CGFloat($0 - position) * width }
  }

  /// Puts `page` in front, brought in on `side`, and slides the strip to it.
  mutating func turn(to page: SlidePage, on side: Side) {
    bring(page, on: side)
    front = page
    position = frontSlot
  }

  /// Sets the pages beside the one in front, for a swipe to show as it drags.
  mutating func peek(left: SlidePage?, right: SlidePage?) {
    if let left { bring(left, on: .left) }
    if let right { bring(right, on: .right) }
  }

  /// Puts `page` on screen beside the page in front on `side`, unless it is already on screen; whatever sat in
  /// that slot gives it up.
  mutating func bring(_ page: SlidePage, on side: Side) {
    guard slots[page] == nil else { return }
    let slot = frontSlot + side.step
    slots = slots.filter { $0.key == front || $0.value != slot }
    slots[page] = slot
  }

  /// Slides the strip by `offset` points from the page in front.
  mutating func follow(_ offset: CGFloat, width: CGFloat) {
    guard width > 0 else { return }
    position = frontSlot - Double(offset / width)
  }

  /// Back to the page in front, for a swipe that springs back.
  mutating func recentre() {
    position = frontSlot
  }

  /// `page` takes the place of the page in front, where it is, without sliding.
  mutating func hand(to page: SlidePage) {
    let slot = frontSlot
    slots[front] = nil
    slots[page] = slot
    front = page
  }

  /// The slide is over: only the page in front stays on screen, at the start of the strip.
  mutating func settle() {
    slots = [front: 0]
    position = 0
  }

  private var frontSlot: Double { slots[front] ?? 0 }
}

/// Draws a page at its slot as the strip slides; only the strip's position animates, so a page given a new slot
/// is there at once.
struct StripPlace: ViewModifier, Animatable {
  var position: Double
  let strip: PageStrip
  let page: SlidePage
  let width: CGFloat

  nonisolated var animatableData: Double {
    get { position }
    set { position = newValue }
  }

  func body(content: Content) -> some View {
    let x = strip.x(of: page, position: position, width: width)
    content
      .offset(x: x ?? 0)
      .opacity(x == nil ? 0 : 1)
  }
}
