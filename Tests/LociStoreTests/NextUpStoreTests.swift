import Foundation
import LociModel
import Testing

@testable import LociStore

/// NX-S1, NX-S4, NX-S8: cards and reminder conditions are kept per home, a declined card stays to be found by
/// its key, and a deleted project takes its own with it.
struct NextUpStoreTests {
  static let project = Fixture.id(40)

  static let target = ApprovalTarget(id: "l-1", name: "家", source: "iCloud")

  static func card(_ seed: UInt64, in home: Home, key: String, state: NextUp.Place = .new) -> NextUp {
    NextUp(
      id: Fixture.id(seed), home: home, key: key, kind: .ask(question: "怎么办"), what: "溢价落到 2.8%", place: state,
      shownAt: Fixture.instant)
  }

  @Test func cardsAreFoundByHomeAndByKey() throws {
    let database = try StoreDatabase.inMemory()
    try database.saveNextUp(Self.card(1, in: .chat, key: "a"))
    try database.saveNextUp(Self.card(2, in: .project(Self.project), key: "a", state: .declined))

    #expect(try database.nextUps(of: [.chat]).map(\.id) == [Fixture.id(1)])
    #expect(try database.nextUps(of: [.chat, .project(Self.project)]).count == 2)
    #expect(try database.nextUp(withKey: "a", in: .project(Self.project))?.place == .declined)
    #expect(try database.nextUp(withKey: "b", in: .chat) == nil)
  }

  @Test func aSavedCardIsWrittenOver() throws {
    let database = try StoreDatabase.inMemory()
    let card = Self.card(1, in: .chat, key: "a")
    try database.saveNextUp(card)
    try database.saveNextUp(card.with(place: .kept))

    #expect(try database.nextUp(card.id)?.place == .kept)
    #expect(try database.nextUps(of: [.chat]).count == 1)
  }

  @Test func aChangeSeesTheCardAsStoredAndCanRefuse() throws {
    let database = try StoreDatabase.inMemory()
    let card = Self.card(1, in: .chat, key: "a")
    try database.saveNextUp(card)

    let writing = NextUp.Execution.writing(marker: "m", into: Self.target)
    let first = try database.changeNextUp(card.id) { $0.execution == .waiting ? $0.with(execution: writing) : nil }
    let second = try database.changeNextUp(card.id) { $0.execution == .waiting ? $0.with(execution: writing) : nil }

    #expect(first?.after?.execution == writing)
    #expect(second?.before.execution == writing && second?.after == nil)
    #expect(try database.changeNextUp(Fixture.id(9)) { $0 } == nil)
  }

  @Test func everyChangeKeepsTheCardOneVersionOnAndNoChangeKeepsItsVersion() throws {
    let database = try StoreDatabase.inMemory()
    let card = Self.card(1, in: .chat, key: "a")
    try database.saveNextUp(card)

    let kept = try database.changeNextUp(card.id) { $0.with(place: .kept) }?.after
    let same = try database.changeNextUp(card.id) { $0 }?.after
    let put = try database.putNextUp(withKey: "a", in: .chat) { $0?.with(what: "改了") }.after

    #expect(kept?.version == card.version + 1)
    #expect(same?.version == card.version + 1)
    #expect(put?.version == card.version + 2)
  }

  @Test func forgettingAProjectKeepsOnlyTheCardsWhoseWritingIsNotSettled() throws {
    let database = try StoreDatabase.inMemory()
    let home = Home.project(Self.project)
    let made = Approved(identifier: "e-1", marker: "m", into: Self.target)
    for (seed, execution) in [
      (1, NextUp.Execution.waiting), (2, .writing(marker: "m", into: Self.target)), (3, .undoing(made)),
      (4, .made(made)),
    ] {
      try database.saveNextUp(
        NextUp(
          id: Fixture.id(UInt64(seed)), home: home, key: "\(seed)",
          kind: .approval(.reminder(ReminderDraft(title: "交房租"))), what: "x", execution: execution,
          shownAt: Fixture.instant))
    }

    try database.forgetProject(Self.project)

    #expect(Set(try database.nextUps(of: [home]).map(\.id)) == [Fixture.id(2), Fixture.id(3)])
  }

  @Test func cardsPutOffComeDueAtTheirTime() throws {
    let database = try StoreDatabase.inMemory()
    let later = Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + 3_600_000)
    try database.saveNextUp(Self.card(1, in: .chat, key: "a", state: .later(until: later)))
    try database.saveNextUp(Self.card(2, in: .chat, key: "b"))

    #expect(try database.nextUpsDue(at: Fixture.instant).isEmpty)
    #expect(try database.nextUpsDue(at: later).map(\.id) == [Fixture.id(1)])
  }

}
