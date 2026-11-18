import Foundation
import LociModel
import Testing

@testable import LociStore

struct EventTests {
  static func at(_ offset: Int64) -> Timestamp {
    Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + offset)
  }

  @Test func eventsComeBackOldestFirstAndFromAMoment() throws {
    let database = try StoreDatabase.inMemory()
    let events = [
      LoggedEvent(id: Fixture.id(10), at: Self.at(0), event: .saved(Fixture.id(2))),
      LoggedEvent(id: Fixture.id(11), at: Self.at(5), event: .highlighted(Fixture.id(2), note: Fixture.id(4))),
      LoggedEvent(id: Fixture.id(12), at: Self.at(9), event: .finishedReading(Fixture.id(3))),
    ]
    for event in events { try database.log(event) }

    #expect(try database.events() == events)
    #expect(try database.events(after: Self.at(5)) == [events[2]])
  }

  @Test func whatHappenedToAnItemGoesWithIt() throws {
    let database = try StoreDatabase.inMemory()
    try database.log(LoggedEvent(id: Fixture.id(10), at: Self.at(0), event: .saved(Fixture.id(2))))
    try database.log(LoggedEvent(id: Fixture.id(11), at: Self.at(1), event: .saved(Fixture.id(3))))

    try database.deleteEvents(about: Fixture.id(2))

    #expect(try database.events().map(\.event) == [.saved(Fixture.id(3))])
  }

  @Test func aDayIsReviewedOnceAndRemembersHowItWent() throws {
    let database = try StoreDatabase.inMemory()
    let day = try #require(Day("2026-11-17"))

    try database.beginReview(of: day, at: Self.at(0))
    #expect(try database.review(of: day) == .started)
    #expect(throws: StoreDatabaseError.alreadyReviewed(day)) { try database.beginReview(of: day, at: Self.at(1)) }
    try database.endReview(of: day, .failed("quota"))
    #expect(try database.review(of: day) == .failed("quota"))
    #expect(try database.review(of: day.adding(days: 1)) == nil)
    #expect(try database.latestReview(before: day.adding(days: 1))?.day == day)
    #expect(try database.latestReview(before: day) == nil)
  }
}
