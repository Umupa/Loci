import LociModel
import Testing

@testable import LociUI

@MainActor
struct HomeSwitchTests {
  private final class Clock {
    var now = ContinuousClock.now
    func advance(_ milliseconds: Int) { now = now.advanced(by: .milliseconds(milliseconds)) }
  }

  private let clock = Clock()
  private let project = Home.project(EntityID())

  private func watching() -> (HomeSwitch, () -> [HomeSwitch.Event]) {
    final class Heard { var events: [HomeSwitch.Event] = [] }
    let heard = Heard()
    let clock = clock
    let watch = HomeSwitch(now: { clock.now }, report: { heard.events.append($0) })
    return (watch, { heard.events })
  }

  @Test func aTurnToAProjectSettlesOnceItsConversationAndPanelsAreBothIn() {
    let (watch, events) = watching()

    watch.turned(to: project, kept: false)
    clock.advance(40)
    watch.arrived(.conversation, in: project)
    clock.advance(25)
    watch.arrived(.panels, in: project)

    #expect(
      events() == [
        .began(project),
        .arrived(.conversation, after: .milliseconds(40)),
        .arrived(.panels, after: .milliseconds(65)),
        .settled(after: .milliseconds(65)),
      ])
  }

  @Test func whatArrivesForAnotherHomeOrAgainIsNotCounted() {
    let (watch, events) = watching()

    watch.turned(to: project, kept: false)
    watch.arrived(.panels, in: .chat)
    clock.advance(10)
    watch.arrived(.panels, in: project)
    clock.advance(10)
    watch.arrived(.panels, in: project)

    #expect(events() == [.began(project), .arrived(.panels, after: .milliseconds(10))])
  }

  @Test func turningAgainBeforeSettlingAbandonsTheEarlierTurn() {
    let (watch, events) = watching()

    watch.turned(to: project, kept: false)
    clock.advance(30)
    watch.turned(to: .chat, kept: true)

    #expect(events().prefix(3) == [.began(project), .abandoned(after: .milliseconds(30)), .began(.chat)])
  }

  @Test func aTurnBackToAPageKeptMadeSettlesAtOnceWhenItHadEverything() {
    let (watch, events) = watching()
    watch.arrived(.conversation, in: .chat)
    watch.arrived(.panels, in: .chat)

    watch.turned(to: .chat, kept: true)

    #expect(events() == [.began(.chat), .settled(after: .zero)])
  }

  @Test func aTurnBackToAPageKeptMadeWaitsForWhatItHasNotHadYet() {
    let (watch, events) = watching()
    watch.arrived(.conversation, in: .chat)

    watch.turned(to: .chat, kept: true)
    clock.advance(15)
    watch.arrived(.panels, in: .chat)

    #expect(
      events() == [.began(.chat), .arrived(.panels, after: .milliseconds(15)), .settled(after: .milliseconds(15))])
  }

  @Test func aPageMadeAgainStartsWithNothingWhateverItHadBefore() {
    let (watch, events) = watching()
    watch.arrived(.conversation, in: project)
    watch.arrived(.panels, in: project)

    watch.turned(to: project, kept: false)

    #expect(events() == [.began(project)])
  }

  @Test func showingAnotherHomeOrLeavingThePageAbandonsTheTurn() {
    let (watch, events) = watching()

    watch.turned(to: project, kept: false)
    watch.shown(project)
    clock.advance(20)
    watch.shown(.chat)
    watch.turned(to: project, kept: false)
    clock.advance(5)
    watch.left()
    watch.left()

    #expect(
      events() == [
        .began(project), .abandoned(after: .milliseconds(20)), .began(project), .abandoned(after: .milliseconds(5)),
      ])
  }
}
