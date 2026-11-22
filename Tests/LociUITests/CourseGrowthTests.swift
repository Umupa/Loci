import Foundation
import LociModel
import Testing

@testable import LociUI

/// The builder's way out of the field or its book and back in, step by step as the page animates it.
struct CourseGrowthTests {
  let raft = BuilderSamples.raft
  let other = EntityID()

  @Test func theBuilderGrowsOutOfWhereItWasAskedForOnceItAppears() {
    var presence = BuilderPresence()
    #expect(presence.follow(raft) == .drawAnew)
    #expect(presence.drawn == raft)
    #expect(presence.grown == 0)
    #expect(presence.follow(raft) == .growOut)
  }

  @Test func theBuilderStaysInViewAllTheWayBackIntoItsBook() {
    var presence = opened()
    #expect(presence.follow(nil) == .goBackIn(raft))
    for grown in [0.75, 0.5, 0.25] {
      presence.grown = grown
      presence.settle(raft)
      #expect(presence.drawn == raft)
    }
    presence.grown = 0
    presence.settle(raft)
    #expect(presence.drawn == nil)
    #expect(presence.follow(nil) == .stay)
  }

  @Test func aBuilderOpenedAgainOnItsWayBackInGrowsOutFromWhereItHadGot() {
    var presence = opened()
    _ = presence.follow(nil)
    presence.grown = 0.4
    #expect(presence.follow(raft) == .growOut)
    presence.settle(raft)
    #expect(presence.drawn == raft)
    #expect(presence.grown == 0.4)
  }

  @Test func anotherBookChosenWhileABuilderGoesBackInKeepsItsOwnBuilder() {
    var presence = opened()
    _ = presence.follow(nil)
    #expect(presence.follow(other) == .drawAnew)
    presence.settle(raft)
    #expect(presence.drawn == other)
  }

  @Test func theBuilderHalfGrownLiesBetweenWhereItCameFromAndItsPlace() {
    let book = CGRect(x: 60, y: 300, width: 150, height: 200)
    let place = CGRect(x: 24, y: 24, width: 1000, height: 832)
    #expect(Growing.frame(at: 0, from: book, to: place) == book)
    #expect(Growing.frame(at: 1, from: book, to: place) == place)
    let half = Growing.frame(at: 0.5, from: book, to: place)
    #expect(half == CGRect(x: 42, y: 162, width: 575, height: 516))
    #expect(Growing.frame(at: 0.5, from: .zero, to: place) == place)
  }

  private func opened() -> BuilderPresence {
    var presence = BuilderPresence()
    _ = presence.follow(raft)
    presence.grown = 1
    return presence
  }
}
