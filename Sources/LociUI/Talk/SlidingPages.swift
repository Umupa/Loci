import LociModel
import SwiftUI

/// The companion's pages side by side in the project bar's order: turning to another slides it in from its
/// side as the one in front slides out, and two fingers across the trackpad drag the pages beside it into view.
/// A page not made yet is made off screen first and slides in once it is there.
struct SlidingPages<Content: View>: View {
  let front: SlidePage
  let order: [Home]
  /// The projects whose pages stay made while others show.
  let kept: [Project.ID]
  /// Whether a new project's page is made, in front or on its way out.
  let newProject: Bool
  /// A project just made from a new project's page, which takes that page's place without sliding.
  let handed: Project.ID?
  /// Changes when the page in front is put there at once, as when the window opens.
  let jump: Int
  /// Whether a swipe may turn pages now.
  let swipes: Bool
  /// Opens the home a swipe turned to; its page is already made.
  let open: (Home) -> Void
  /// The slide is over and only the page in front is on screen.
  let settled: () -> Void
  @ViewBuilder let content: (SlidePage) -> Content
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var strip = PageStrip(front: .home(.chat))
  /// What the slides keep track of without drawing anything again.
  @State private var turning = Turning()
  @State private var width: CGFloat = 0

  var body: some View {
    ZStack(alignment: .top) {
      ForEach(pages, id: \.self) { page in
        content(page)
          .modifier(StripPlace(position: strip.position, strip: strip, page: page, width: width))
          .onAppear { appeared(page) }
          .onDisappear { turning.made.remove(page) }
      }
    }
    .clipped()
    .background { PageSwipe(enabled: swipes && !newProject, actions: swipe) }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
    .onChange(of: front) { turn(to: front) }
    .onChange(of: jump) {
      turning.arriving = nil
      strip = PageStrip(front: front)
    }
  }

  /// The chat's page, the kept projects' and any other on screen, then a new project's.
  private var pages: [SlidePage] {
    let passing = strip.onScreen.compactMap { page -> Project.ID? in
      guard case .home(.project(let id)) = page, !kept.contains(id) else { return nil }
      return id
    }
    return [.home(.chat)] + (kept + passing).map { .home(.project($0)) } + (newProject ? [.newProject] : [])
  }

  private func turn(to page: SlidePage) {
    turning.arriving = nil
    if case .home(.project(let id)) = page, strip.front == .newProject, id == handed {
      strip.hand(to: page)
      return
    }
    guard let side = HomeSlide.side(from: strip.front, to: page, in: order) else { return }
    if reduceMotion {
      strip.turn(to: page, on: side)
      finish()
    } else if turning.made.contains(page) {
      slide { strip.turn(to: page, on: side) }
    } else {
      strip.bring(page, on: side)
      turning.arriving = (page, side)
    }
  }

  private func appeared(_ page: SlidePage) {
    turning.made.insert(page)
    guard let arriving = turning.arriving, arriving.page == page else { return }
    turning.arriving = nil
    if strip.front != page { slide { strip.turn(to: page, on: arriving.side) } }
  }

  private func slide(_ change: () -> Void) {
    turning.serial += 1
    let mine = turning.serial
    withAnimation(Motion.pageTurn, change) {
      if turning.serial == mine { finish() }
    }
  }

  private func finish() {
    strip.settle()
    settled()
  }

  private var swipe: PageSwipeActions {
    PageSwipeActions(
      began: {
        guard case .home(let home) = strip.front else { return }
        turning.serial += 1
        strip.peek(
          left: HomeSlide.neighbour(of: home, on: .left, in: order).map(SlidePage.home),
          right: HomeSlide.neighbour(of: home, on: .right, in: order).map(SlidePage.home))
      },
      moved: { offset in
        guard case .home(let home) = strip.front, !reduceMotion else { return }
        let toward: Side = offset < 0 ? .right : .left
        let end = HomeSlide.neighbour(of: home, on: toward, in: order) == nil
        strip.follow(end ? HomeSlide.resisted(offset, width: width) : offset, width: width)
      },
      ended: { offset, velocity in
        if case .home(let home) = strip.front, let velocity,
          let side = HomeSlide.outcome(offset: offset, velocity: velocity, width: width),
          let next = HomeSlide.neighbour(of: home, on: side, in: order)
        {
          open(next)
        } else if reduceMotion {
          finish()
        } else {
          slide { strip.recentre() }
        }
      })
  }
}

/// The pages made so far, the one waiting to be made before it slides in, and which slide is the latest, so only
/// its end settles the strip.
@MainActor
private final class Turning {
  var made: Set<SlidePage> = []
  var arriving: (page: SlidePage, side: Side)?
  var serial = 0
}
