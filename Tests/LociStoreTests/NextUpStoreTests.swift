import Foundation
import LociModel
import Testing

@testable import LociStore

/// NX-S1, NX-S4, NX-S8: cards and reminder conditions are kept per home, a declined card stays to be found by
/// its key, and a deleted project takes its own with it.
struct NextUpStoreTests {
  static let project = Fixture.id(40)

  static func card(_ seed: UInt64, in home: Home, key: String, state: NextUp.State = .new) -> NextUp {
    NextUp(
      id: Fixture.id(seed), home: home, key: key, kind: .ask(question: "怎么办"), what: "溢价落到 2.8%", state: state,
      shownAt: Fixture.instant)
  }

  static func condition(_ seed: UInt64, in home: Home) -> NextUpCondition {
    NextUpCondition(
      id: Fixture.id(seed), home: home, field: SourceField("prem.513100.premium")!, comparison: .below,
      threshold: 0.03, say: "溢价 {value}", ask: "要不要申购", createdAt: Fixture.instant)
  }

  @Test func cardsAreFoundByHomeAndByKey() throws {
    let database = try StoreDatabase.inMemory()
    try database.saveNextUp(Self.card(1, in: .chat, key: "a"))
    try database.saveNextUp(Self.card(2, in: .project(Self.project), key: "a", state: .declined))

    #expect(try database.nextUps(of: [.chat]).map(\.id) == [Fixture.id(1)])
    #expect(try database.nextUps(of: [.chat, .project(Self.project)]).count == 2)
    #expect(try database.nextUp(withKey: "a", in: .project(Self.project))?.state == .declined)
    #expect(try database.nextUp(withKey: "b", in: .chat) == nil)
  }

  @Test func aSavedCardIsWrittenOver() throws {
    let database = try StoreDatabase.inMemory()
    let card = Self.card(1, in: .chat, key: "a")
    try database.saveNextUp(card)
    try database.saveNextUp(card.with(state: .kept))

    #expect(try database.nextUp(card.id)?.state == .kept)
    #expect(try database.nextUps(of: [.chat]).count == 1)
  }

  @Test func cardsPutOffComeDueAtTheirTime() throws {
    let database = try StoreDatabase.inMemory()
    let later = Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + 3_600_000)
    try database.saveNextUp(Self.card(1, in: .chat, key: "a", state: .later(until: later)))
    try database.saveNextUp(Self.card(2, in: .chat, key: "b"))

    #expect(try database.nextUpsDue(at: Fixture.instant).isEmpty)
    #expect(try database.nextUpsDue(at: later).map(\.id) == [Fixture.id(1)])
  }

  @Test func conditionsAreFoundByHomeAndBySource() throws {
    let database = try StoreDatabase.inMemory()
    try database.saveNextUpCondition(Self.condition(1, in: .chat))
    try database.saveNextUpCondition(Self.condition(2, in: .project(Self.project)))

    #expect(try database.nextUpConditions(of: .chat).map(\.id) == [Fixture.id(1)])
    #expect(try database.nextUpConditions(on: SourceKey(.project(Self.project), "prem")).map(\.id) == [Fixture.id(2)])
    #expect(try database.removeNextUpCondition(Fixture.id(1)))
    #expect(try database.nextUpConditions(of: .chat).isEmpty)
  }

  @Test func aDeletedProjectsCardsAndConditionsGoWithIt() throws {
    let database = try StoreDatabase.inMemory()
    try database.saveNextUp(Self.card(1, in: .chat, key: "a"))
    try database.saveNextUp(Self.card(2, in: .project(Self.project), key: "a"))
    try database.saveNextUpCondition(Self.condition(3, in: .project(Self.project)))

    try database.forgetNextUps(of: Self.project)

    #expect(try database.nextUps(of: [.chat, .project(Self.project)]).map(\.id) == [Fixture.id(1)])
    #expect(try database.nextUpConditions(of: .project(Self.project)).isEmpty)
  }
}
