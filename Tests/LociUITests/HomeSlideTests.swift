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

  @Test func turningAgainBeforeTheSlideEndsHeadsStraightForTheNewPage() {
    var strip = PageStrip(front: .home(.chat))
    strip.turn(to: .home(.project(a)), on: .right)
    strip.turn(to: .home(.project(b)), on: .right)

    #expect(strip.position == 2)
    #expect(strip.x(of: .home(.project(b)), position: strip.position, width: width) == 0)
    #expect(strip.x(of: .home(.chat), position: strip.position, width: width) == -2 * width)
    #expect(strip.onScreen == [.home(.chat), .home(.project(a)), .home(.project(b))])
  }

  @Test func turningBackMidSlideReturnsToThePageItCameFrom() {
    var strip = PageStrip(front: .home(.chat))
    strip.turn(to: .home(.project(a)), on: .right)
    strip.turn(to: .home(.chat), on: .left)

    #expect(strip.position == 0)
    #expect(strip.x(of: .home(.chat), position: strip.position, width: width) == 0)
  }

  @Test func aPageGoneByWhenTheSlideEndsIsPutAway() {
    var strip = PageStrip(front: .home(.chat))
    strip.turn(to: .home(.project(a)), on: .right)
    strip.settle()

    #expect(strip.onScreen == [.home(.project(a))])
    #expect(strip.position == 0)
    #expect(strip.x(of: .home(.project(a)), position: strip.position, width: width) == 0)
  }

  @Test func aPeekedNeighbourSitsJustBesideThePageInFront() {
    var strip = PageStrip(front: .home(.project(a)))
    strip.peek(left: .home(.chat), right: .home(.project(b)))

    #expect(strip.x(of: .home(.chat), position: strip.position, width: width) == -width)
    #expect(strip.x(of: .home(.project(b)), position: strip.position, width: width) == width)
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
