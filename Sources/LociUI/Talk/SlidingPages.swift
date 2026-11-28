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
  let travel: PageTravel
  /// Opens the home a swipe turned to; its page is already made.
  let open: (Home) -> Void
  /// The slide to this page is over and only it is on screen.
  let settled: (SlidePage) -> Void
  var now: () -> ContinuousClock.Instant = { .now }
  @ViewBuilder let content: (SlidePage) -> Content
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var strip = PageStrip(front: .home(.chat))
  /// What the slides keep track of without drawing anything again.
  @State private var turning = Turning()
  @State private var width: CGFloat = 0

  var body: some View {
    ZStack(alignment: .top) {
      ForEach(pages, id: \.self) { page in
        PlacedPage(travel: travel, slot: strip.slot(of: page), width: width) { content(page) }
          .onAppear { appeared(page) }
          .onDisappear { travel.made.remove(page) }
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
    .onChange(of: jump, initial: true) {
      turning.arriving = nil
      turning.flight = nil
      strip = PageStrip(front: front)
      travel.position = 0
      travel.pull = 0
      travel.heading = front
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

  /// Where the strip is shown now, partway through a slide or not.
  private var shown: Double { turning.flight?.position(at: now()) ?? travel.position }

  private func turn(to page: SlidePage) {
    turning.arriving = nil
    let speed = turning.release ?? 0
    turning.release = nil
    if case .home(.project(let id)) = page, strip.front == .newProject, id == handed {
      strip.hand(to: page)
      travel.heading = page
      finish()
      return
    }
    guard let side = HomeSlide.side(from: strip.front, to: page, in: order) else { return }
    if reduceMotion {
      strip.turn(to: page, on: side, from: travel.position)
      travel.heading = page
      finish()
    } else if travel.made.contains(page) {
      strip.turn(to: page, on: side, from: shown)
      slide(speed: speed)
    } else {
      strip.bring(page, on: side, from: shown)
      turning.arriving = (page, side)
    }
  }

  private func appeared(_ page: SlidePage) {
    travel.made.insert(page)
    guard let arriving = turning.arriving, arriving.page == page else { return }
    turning.arriving = nil
    guard strip.front != page else { return }
    strip.turn(to: page, on: arriving.side, from: shown)
    slide(speed: 0)
  }

  /// Slides the strip to the page in front from where it is shown, setting off at `speed` pages a second; the
  /// bar's slider lets go of the fingers' pull with it.
  private func slide(speed: Double) {
    turning.serial += 1
    let mine = turning.serial
    let flight = PageFlight(from: shown, to: strip.frontPosition, speed: speed, start: now())
    turning.flight = flight
    if travel.heading != strip.front { travel.heading = strip.front }
    withAnimation(flight.animation) {
      travel.position = flight.to
      travel.pull = 0
    } completion: {
      if turning.serial == mine { finish() }
    }
  }

  private func finish() {
    turning.flight = nil
    strip.settle()
    travel.position = 0
    travel.pull = 0
    settled(strip.front)
  }

  private var swipe: PageSwipeActions {
    PageSwipeActions(
      began: {
        guard case .home(let home) = strip.front else { return }
        turning.serial += 1
        turning.release = nil
        let from = shown
        turning.flight = nil
        travel.position = from
        turning.drawn = CGFloat(strip.frontPosition - from) * width
        strip.peek(
          left: HomeSlide.neighbour(of: home, on: .left, in: order).map(SlidePage.home),
          right: HomeSlide.neighbour(of: home, on: .right, in: order).map(SlidePage.home), from: from)
      },
      moved: { offset in
        guard case .home(let home) = strip.front, !reduceMotion, width > 0 else { return }
        let total = turning.drawn + offset
        let toward: Side = total < 0 ? .right : .left
        let end = HomeSlide.neighbour(of: home, on: toward, in: order) == nil
        let drawn = end ? HomeSlide.resisted(total, width: width) : total
        travel.position = strip.position(dragged: drawn, width: width)
        travel.pull = end ? 0 : max(-1, min(1, -Double(drawn / width)))
      },
      ended: { offset, velocity in
        let total = turning.drawn + offset
        turning.drawn = 0
        let speed = width > 0 ? -Double((velocity ?? 0) / width) : 0
        if case .home(let home) = strip.front, let velocity,
          let side = HomeSlide.outcome(offset: total, velocity: velocity, width: width),
          let next = HomeSlide.neighbour(of: home, on: side, in: order)
        {
          turning.release = speed
          open(next)
        } else if reduceMotion {
          finish()
        } else {
          slide(speed: speed)
        }
      })
  }
}

/// Where the companion's pages are as they slide, apart from the pages themselves, so a slide or a drag moves
/// them without making any page again; the project bar follows it too.
@MainActor
@Observable
final class PageTravel {
  /// Where the strip of pages is, in pages from its start; it animates as they slide.
  var position: Double = 0
  /// How far two fingers have drawn the page in front toward the one beside it, in pages; toward the right one
  /// above zero.
  var pull: Double = 0
  /// The page in front, or the one the pages are sliding to.
  var heading: SlidePage = .home(.chat)
  /// The pages made so far.
  @ObservationIgnored var made: Set<SlidePage> = []

  /// Shows the pages going to `page` as soon as it is chosen, when its page is made and so slides at once. A page
  /// still to be made is shown as where they are going once it starts to slide in. Changing it with the choice,
  /// before the slide starts, keeps the bar's change out of the slide's first frame, which would cost it dearly.
  func head(to page: SlidePage) {
    if made.contains(page), heading != page { heading = page }
  }
}

/// One page at its slot along the strip; only this follows the strip as it moves.
private struct PlacedPage<Content: View>: View {
  let travel: PageTravel
  let slot: Double?
  let width: CGFloat
  @ViewBuilder let content: Content

  var body: some View {
    content.modifier(StripPlace(position: travel.position, slot: slot, width: width))
  }
}

/// The page waiting to be made before it slides in, the slide under way, how far a swipe begun mid-slide found
/// the page already drawn, the speed a swipe let go with, and which slide is the latest, so only its end settles
/// the strip.
@MainActor
private final class Turning {
  var arriving: (page: SlidePage, side: Side)?
  var flight: PageFlight?
  var drawn: CGFloat = 0
  var release: Double?
  var serial = 0
}
