import Foundation
import Testing

@testable import LociModel

/// NX-S1, NX-S2, NX-S4, NX-S7: the deck's order, reminder conditions that fire only as they turn true, and
/// approvals that can only be an event or a reminder.
struct NextUpTests {
  static func at(minutes: Int64) -> Timestamp {
    Timestamp(millisecondsSince1970: 1_763_337_600_000 + minutes * 60_000)
  }

  static func id(_ seed: UInt64) -> EntityID {
    var entropy = SeededGenerator(seed: seed)
    return EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + Double(seed)), entropy: &entropy)
  }

  static func card(_ seed: UInt64, _ state: NextUp.State = .new, shown minutes: Int64) -> NextUp {
    NextUp(
      id: id(seed), home: .chat, key: "\(seed)", kind: .ask(question: "?"), what: "\(seed)", state: state,
      shownAt: at(minutes: minutes))
  }

  static func snapshot(_ premium: Double) -> SourceSnapshot {
    SourceSnapshot(fetched: at(minutes: 0), records: ["513100": ["premium": .number(premium)]])
  }

  static let condition = NextUpCondition(
    id: id(9), home: .chat, field: SourceField("prem.513100.premium")!, comparison: .below, threshold: 0.03,
    say: "513100 溢价回到 {value}", ask: "要不要现在申购？", createdAt: at(minutes: 0))

  @Test func theDeckShowsNewCardsAboveKeptOnesTheLatestFirst() {
    let cards = [
      Self.card(1, shown: 1), Self.card(2, .kept, shown: 5), Self.card(3, shown: 3), Self.card(4, .declined, shown: 9),
      Self.card(5, .started, shown: 9),
    ]

    #expect(NextUp.deck(cards, at: Self.at(minutes: 10)).map(\.what) == ["3", "1", "2"])
  }

  @Test func aCardPutOffIsHiddenUntilItsTimeAndThenComesToTheTop() {
    let cards = [Self.card(1, .later(until: Self.at(minutes: 60)), shown: 0), Self.card(2, shown: 30)]

    #expect(NextUp.deck(cards, at: Self.at(minutes: 59)).map(\.what) == ["2"])
    #expect(NextUp.deck(cards, at: Self.at(minutes: 60)).map(\.what) == ["1", "2"])
  }

  @Test func aConditionFiresOnlyWhenItTurnsTrue() {
    var condition = Self.condition
    var fired: [String] = []
    for (minutes, premium) in [(0, 0.034), (10, 0.028), (20, 0.027), (30, 0.025)] as [(Int64, Double)] {
      let step = condition.step(Self.snapshot(premium), at: Self.at(minutes: minutes))
      condition = step.0
      if let words = step.fired { fired.append(words) }
    }

    #expect(fired == ["513100 溢价回到 0.028"])
    #expect(condition.holds == true)
  }

  @Test func aConditionAlreadyTrueWhenSetDoesNotFire() {
    let step = Self.condition.step(Self.snapshot(0.02), at: Self.at(minutes: 0))

    #expect(step.fired == nil)
    #expect(step.0.holds == true)
  }

  @Test func aConditionFiresAgainAfterRisingAndFallingOnceRested() {
    var condition = Self.condition.with(holds: false, firedAt: nil)
    var fired: [Int64] = []
    for (minutes, premium) in [(0, 0.028), (60, 0.031), (120, 0.029), (300, 0.032), (301, 0.029)] as [(Int64, Double)] {
      let step = condition.step(Self.snapshot(premium), at: Self.at(minutes: minutes))
      condition = step.0
      if step.fired != nil { fired.append(minutes) }
    }

    #expect(fired == [0, 301])
  }

  @Test func aMissingValueLeavesAConditionAsItWas() {
    let condition = Self.condition.with(holds: false, firedAt: nil)
    let empty = SourceSnapshot(fetched: Self.at(minutes: 0), records: [:])

    #expect(condition.step(empty, at: Self.at(minutes: 1)).0 == condition)
    #expect(condition.step(empty, at: Self.at(minutes: 1)).fired == nil)
  }

  @Test func anApprovalCanOnlyBeAnEventOrAReminder() throws {
    let event = Approval.event(EventDraft(title: "投资复盘", start: Self.at(minutes: 0)))
    let data = try JSONEncoder().encode(event)
    #expect(try JSONDecoder().decode(Approval.self, from: data) == event)

    let payment = Data(#"{"payment":{"_0":{"amount":30000}}}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Approval.self, from: payment) }
  }

  @Test func theSameWordsHaveTheSameKey() {
    #expect(NextUp.key(of: "JR Pass 12 月起涨价。") == NextUp.key(of: "jr pass  12月起涨价"))
  }
}
