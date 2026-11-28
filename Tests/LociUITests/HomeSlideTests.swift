import CoreGraphics
import LociModel
import Testing

@testable import LociUI

/// PJ-S16, PJ-S17: pages turn sideways in the project bar's order, and a swipe turns them when it goes far or
/// fast enough.
@MainActor
struct HomeSlideTests {
  private let a = ProjectSnapshots.id(1)
  private let b = ProjectSnapshots.id(2)
  private let c = ProjectSnapshots.id(3)
  private let width: CGFloat = 1000

  private var order: [Home] { [.chat, .project(a), .project(b), .project(c)] }

  @Test func theOrderIsTheChatThenTheProjectsThenTheArchivedAsTheBarAndItsListShowThem() {
    let project = { (id: Project.ID) in Project(id: id, name: "p", createdAt: Timestamp(millisecondsSince1970: 1)) }
    let bar = ProjectBar(projects: [project(b), project(a)], archived: [project(c)])

    #expect(HomeSlide.order(of: bar) == [.chat, .project(b), .project(a), .project(c)])
  }

  @Test func aProjectRightOfTheOpenOneComesInFromTheRight() {
    #expect(HomeSlide.side(from: .home(.project(a)), to: .home(.project(c)), in: order) == .right)
  }

  @Test func theChatComesBackFromTheLeft() {
    #expect(HomeSlide.side(from: .home(.project(b)), to: .home(.chat), in: order) == .left)
  }

  @Test func turningToThePageAlreadyInFrontGoesNowhere() {
    #expect(HomeSlide.side(from: .home(.project(b)), to: .home(.project(b)), in: order) == nil)
  }

  @Test func theNewProjectPageComesInFromTheRightOfEverything() {
    #expect(HomeSlide.side(from: .home(.project(c)), to: .newProject, in: order) == .right)
    #expect(HomeSlide.side(from: .newProject, to: .home(.project(c)), in: order) == .left)
  }

  @Test func goingBackFromAProjectJustDeletedSlidesBackFromTheRight() {
    let gone = Home.project(ProjectSnapshots.id(9))

    #expect(HomeSlide.side(from: .home(gone), to: .home(.chat), in: order) == .left)
  }

  @Test func theChatHasNothingToItsLeftAndTheLastProjectNothingToItsRight() {
    #expect(HomeSlide.neighbour(of: .chat, on: .left, in: order) == nil)
    #expect(HomeSlide.neighbour(of: .chat, on: .right, in: order) == .project(a))
    #expect(HomeSlide.neighbour(of: .project(c), on: .right, in: order) == nil)
    #expect(HomeSlide.neighbour(of: .project(c), on: .left, in: order) == .project(b))
  }

  @Test func theNewProjectPageIsNeverTurnedToBySwiping() {
    for home in order {
      #expect(HomeSlide.neighbour(of: home, on: .right, in: order).map(SlidePage.home) != .newProject)
    }
    #expect(HomeSlide.neighbour(of: .project(c), on: .right, in: order) == nil)
  }

  @Test func aLongEnoughDragTurnsThePage() {
    #expect(HomeSlide.outcome(offset: -620, velocity: 0, width: width) == .right)
    #expect(HomeSlide.outcome(offset: 620, velocity: 0, width: width) == .left)
  }

  @Test func aShortQuickFlickTurnsThePage() {
    #expect(HomeSlide.outcome(offset: -120, velocity: -2600, width: width) == .right)
  }

  @Test func aShortSlowDragSpringsBack() {
    #expect(HomeSlide.outcome(offset: -200, velocity: -100, width: width) == nil)
  }

  @Test func aFlickBackAgainstTheDragSpringsBack() {
    #expect(HomeSlide.outcome(offset: -560, velocity: 900, width: width) == nil)
  }

  @Test func dragsPastTheEndGiveLessAndLess() {
    let little = HomeSlide.resisted(100, width: width)
    let more = HomeSlide.resisted(400, width: width)
    let most = HomeSlide.resisted(4000, width: width)

    #expect(little > 0 && little < 100)
    #expect(more > little && more - little < 300)
    #expect(most < width / 2)
    #expect(HomeSlide.resisted(-400, width: width) == -more)
  }

  @Test func aMostlyVerticalScrollIsLeftToTheConversation() {
    #expect(SwipeClaim.decide(dx: 3, dy: 2) == nil)
    #expect(SwipeClaim.decide(dx: 9, dy: 14) == .pass)
    #expect(SwipeClaim.decide(dx: 12, dy: 8) == .pass)
  }

  @Test func aMostlyHorizontalOneTurnsPages() {
    #expect(SwipeClaim.decide(dx: -14, dy: 3) == .claim)
  }

  @Test func anOrdinaryFlickTowardTheNextPageTurnsIt() {
    #expect(HomeSlide.outcome(offset: -150, velocity: -600, width: width) == .right)
    #expect(HomeSlide.outcome(offset: 150, velocity: 600, width: width) == .left)
  }

  @Test func turningAgainBeforeTheSlideEndsHeadsStraightForTheNewPage() {
    var strip = PageStrip(front: .home(.chat))
    strip.turn(to: .home(.project(a)), on: .right, from: 0)
    strip.turn(to: .home(.project(b)), on: .right, from: 0)

    #expect(strip.frontPosition == 2)
    #expect(strip.x(of: .home(.project(b)), position: 2, width: width) == 0)
    #expect(strip.x(of: .home(.chat), position: 2, width: width) == -2 * width)
    #expect(strip.onScreen == [.home(.chat), .home(.project(a)), .home(.project(b))])
  }

  @Test func turningBackMidSlideReturnsToThePageItCameFrom() {
    var strip = PageStrip(front: .home(.chat))
    strip.turn(to: .home(.project(a)), on: .right, from: 0)
    strip.turn(to: .home(.chat), on: .left, from: 0.5)

    #expect(strip.frontPosition == 0)
    #expect(strip.x(of: .home(.chat), position: 0, width: width) == 0)
  }

  @Test func turningMidSlideNeverTakesAwayAPageStillOnScreen() {
    var strip = PageStrip(front: .home(.chat))
    strip.turn(to: .home(.project(a)), on: .right, from: 0)
    strip.turn(to: .home(.project(c)), on: .left, from: 0.5)

    #expect(strip.x(of: .home(.chat), position: 0.5, width: width) == -width / 2)
    #expect(strip.x(of: .home(.project(a)), position: 0.5, width: width) == width / 2)
    #expect(strip.frontPosition == -1)
  }

  @Test func aPageGoneByWhenTheSlideEndsIsPutAway() {
    var strip = PageStrip(front: .home(.chat))
    strip.turn(to: .home(.project(a)), on: .right, from: 0)
    strip.settle()

    #expect(strip.onScreen == [.home(.project(a))])
    #expect(strip.frontPosition == 0)
    #expect(strip.x(of: .home(.project(a)), position: 0, width: width) == 0)
  }

  @Test func aPeekedNeighbourSitsJustBesideThePageInFront() {
    var strip = PageStrip(front: .home(.project(a)))
    strip.peek(left: .home(.chat), right: .home(.project(b)), from: 0)

    #expect(strip.x(of: .home(.chat), position: 0, width: width) == -width)
    #expect(strip.x(of: .home(.project(b)), position: 0, width: width) == width)
  }

  @Test func theFingersDrawTheStripAlongWithThem() {
    var strip = PageStrip(front: .home(.chat))
    strip.turn(to: .home(.project(a)), on: .right, from: 0)

    #expect(strip.position(dragged: -250, width: width) == 1.25)
    #expect(strip.position(dragged: 500, width: width) == 0.5)
  }

  @Test func aPageLetGoMidSwipeCarriesOnAtTheFingersSpeedAndComesToRestOnItsPage() {
    let start = ContinuousClock.now
    let flight = PageFlight(from: 0.3, to: 1, speed: 3, start: start)

    #expect(flight.position(at: start) == 0.3)
    #expect(flight.position(at: start + .milliseconds(16)) > 0.3 + 0.016 * 3 * 0.8)
    #expect(abs(flight.position(at: start + .seconds(2)) - 1) < 0.001)
  }

  @Test func aPageTurnedFromRestSetsOffGentlyAndDoesNotOvershoot() {
    let start = ContinuousClock.now
    let flight = PageFlight(from: 0, to: 1, speed: 0, start: start)
    let positions = (0...60).map { flight.position(at: start + .milliseconds($0 * 10)) }

    #expect(positions[1] < 0.05)
    #expect(positions.allSatisfy { $0 <= 1 + 0.0001 })
    #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 <= $1 })
  }

  @Test func theBarsSliderFollowsTheFingersTowardTheTabBesideTheOpenOne() {
    let tabs: [SlidePage: CGRect] = [
      .home(.chat): CGRect(x: 0, y: 0, width: 60, height: 30),
      .home(.project(a)): CGRect(x: 70, y: 0, width: 100, height: 30),
      .home(.project(b)): CGRect(x: 180, y: 0, width: 30, height: 30),
    ]
    let open = SlidePage.home(.project(a))

    #expect(HomeSlide.slider(over: tabs, open: open, pull: 0, in: order) == tabs[open])
    #expect(
      HomeSlide.slider(over: tabs, open: open, pull: 0.5, in: order) == CGRect(x: 125, y: 0, width: 65, height: 30))
    #expect(
      HomeSlide.slider(over: tabs, open: open, pull: -0.5, in: order) == CGRect(x: 35, y: 0, width: 80, height: 30))
    #expect(
      HomeSlide.slider(over: tabs, open: .home(.chat), pull: -0.5, in: order) == tabs[.home(.chat)])
  }
}

/// PJ-S17: a swipe mostly across takes the page, with its momentum; anything else is left to scroll.
struct SwipeTrackerTests {
  private func run(
    _ steps: [(SwipeTracker.Step, CGFloat, CGFloat)], inside: Bool = true, scrollsAcross: Bool = false
  ) -> [(taken: Bool, told: [SwipeTracker.Told])] {
    var tracker = SwipeTracker()
    return steps.enumerated().map { index, step in
      tracker.take(
        step.0, dx: step.1, dy: step.2, at: Double(index) * 0.016, inside: inside, scrollsAcross: { scrollsAcross })
    }
  }

  @Test func aSwipeAcrossIsTakenAndTellsThePageHowFarAndHowFast() {
    let results = run([(.began, -2, 0), (.changed, -10, 1), (.changed, -20, 0), (.ended, 0, 0)])

    #expect(results.map(\.taken) == [false, true, true, true])
    #expect(results[1].told == [.began, .moved(-12)])
    #expect(results[2].told == [.moved(-32)])
    guard case .ended(let offset, let velocity?) = results[3].told.first else {
      Issue.record("the swipe did not end with a speed")
      return
    }
    #expect(offset == -32)
    #expect(velocity < -500)
  }

  @Test func theMomentumAfterATakenSwipeIsTakenToo() {
    let results = run([
      (.began, -2, 0), (.changed, -12, 0), (.ended, 0, 0), (.momentum(last: false), -30, 0),
      (.momentum(last: true), 0, 0),
    ])

    #expect(results.map(\.taken) == [false, true, true, true, true])
    #expect(results[3].told.isEmpty)
  }

  @Test func aScrollMostlyUpOrDownAndItsMomentumAreLeftAlone() {
    let results = run([
      (.began, 0, 3), (.changed, 6, 14), (.changed, -40, 2), (.ended, 0, 0), (.momentum(last: false), -40, 0),
    ])

    #expect(results.allSatisfy { !$0.taken && $0.told.isEmpty })
  }

  @Test func aSwipeOverSomethingThatScrollsAcrossByItselfIsLeftToIt() {
    let results = run([(.began, -2, 0), (.changed, -14, 0), (.ended, 0, 0)], scrollsAcross: true)

    #expect(results.allSatisfy { !$0.taken })
  }

  @Test func aSwipeBegunOutsideThePagesOrWhileTheyMayNotTurnIsLeftAlone() {
    let results = run([(.began, -2, 0), (.changed, -14, 0), (.ended, 0, 0)], inside: false)

    #expect(results.allSatisfy { !$0.taken })
  }

  @Test func aSwipeTheSystemCallsOffEndsWithoutASpeed() {
    let results = run([(.began, -2, 0), (.changed, -14, 0), (.cancelled, 0, 0)])

    #expect(results[2].told == [.ended(-16, velocity: nil)])
  }
}
