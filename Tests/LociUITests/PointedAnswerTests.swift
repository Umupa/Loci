import LociModel
import Testing

@testable import LociUI

@MainActor
struct PointedAnswerTests {
  @Test func theAnswerUnderThePointerIsTheOneWhoseActionsShow() {
    let pointed = PointedAnswer()
    let first = EntityID()
    let second = EntityID()

    pointed.hovering(true, over: first)
    #expect(pointed.id == first)
    pointed.hovering(false, over: first)
    pointed.hovering(true, over: second)
    #expect(pointed.id == second)
  }

  @Test func leavingAnotherAnswerKeepsTheOneThePointerIsOver() {
    let pointed = PointedAnswer()
    let first = EntityID()
    let second = EntityID()

    pointed.hovering(true, over: second)
    pointed.hovering(false, over: first)

    #expect(pointed.id == second)
  }

  @Test func leavingTheAnswerHidesItsActions() {
    let pointed = PointedAnswer()
    let answer = EntityID()

    pointed.hovering(true, over: answer)
    pointed.hovering(false, over: answer)

    #expect(pointed.id == nil)
  }
}
