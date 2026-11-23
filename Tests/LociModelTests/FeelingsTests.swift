import Foundation
import Testing

@testable import LociModel

struct FeelingsTests {
  static let zone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt

  /// 2025-11-17 at `hour:minute` in Shanghai.
  static func at(_ hour: Int, _ minute: Int = 0, days: Int = 0) -> Timestamp {
    let midnight = Fixture.instant.millisecondsSince1970 - 8 * 3_600_000 - 123
    return Timestamp(millisecondsSince1970: midnight + Int64((days * 24 + hour) * 60 + minute) * 60_000)
  }

  static func score(_ value: Int) -> Score { Score(value) ?? Score(nearest: Double(value)) }

  @Test func eachMessageTiresAndQuietTimeRests() {
    var fatigue = Fatigue()
    for minute in 0..<20 { fatigue.heard(at: Self.at(10, minute), in: Self.zone) }
    #expect(fatigue.felt(at: Self.at(10, 19), in: Self.zone).amount == 15)

    #expect(fatigue.felt(at: Self.at(10, 29), in: Self.zone).amount == 7)
    #expect(fatigue.felt(at: Self.at(11), in: Self.zone).amount == 0)
  }

  @Test func theNightPullsTirednessUp() {
    let fatigue = Fatigue(amount: 20, lastHeard: Self.at(23))
    #expect(fatigue.felt(at: Self.at(23), in: Self.zone) == (35, .tired))
    #expect(Fatigue(amount: 25, lastHeard: Self.at(2)).felt(at: Self.at(2), in: Self.zone) == (55, .sleepy))
    #expect(Fatigue(amount: 50, lastHeard: Self.at(3)).felt(at: Self.at(3), in: Self.zone) == (80, .asleep))
    #expect(Fatigue(amount: 25, lastHeard: Self.at(10)).felt(at: Self.at(10), in: Self.zone) == (25, .awake))
  }

  @Test func goingToSleepIsAsleepWhateverTheAmount() {
    var fatigue = Fatigue()
    fatigue.sleep(at: Self.at(23))
    #expect(fatigue.felt(at: Self.at(23, 5), in: Self.zone).tiredness == .asleep)
  }

  @Test func wokenByHandStaysAwakeForTwoHoursExceptDeepInTheNight() {
    var fatigue = Fatigue(amount: 90, lastHeard: Self.at(22))
    fatigue.sleep(at: Self.at(22))
    fatigue.wake(at: Self.at(22, 30))
    #expect(fatigue.felt(at: Self.at(22, 30), in: Self.zone).tiredness == .awake)
    #expect(fatigue.felt(at: Self.at(1, days: 1), in: Self.zone).tiredness != .awake)

    fatigue.heard(at: Self.at(0, 31, days: 1), in: Self.zone)
    #expect(fatigue.rest == .awake)
  }

  @Test func asleepMoreThanTwoHoursInTheDayWakesByItself() {
    var night = Fatigue(amount: 60)
    night.sleep(at: Self.at(1))
    night.heard(at: Self.at(5), in: Self.zone)
    #expect(night.rest == .asleep(since: Self.at(1)))

    var nap = Fatigue(amount: 60)
    nap.sleep(at: Self.at(13))
    nap.wakeIfRested(at: Self.at(14), in: Self.zone)
    #expect(nap.rest == .asleep(since: Self.at(13)))
    nap.wakeIfRested(at: Self.at(15, 1), in: Self.zone)
    #expect(nap.rest == .awake)
    #expect(nap.amount == 20)
  }

  @Test func withoutAnyMoodTheCompanionIsItsRestingSelf() {
    let felt = Moods().felt(in: .main, at: Self.at(10))
    #expect(felt.word == "cheerful")
    #expect(felt.valence.value == 6)
    #expect(felt.energy.value == 7)
    #expect(felt.here == nil)
  }

  @Test func aConversationMoodWeighsMoreThanTheBaseMood() {
    let base = BaseMood(
      mood: Mood(word: "low", valence: Self.score(3), why: "rain", at: Self.at(10)), energy: Self.score(4))
    let here = Mood(word: "pleased", valence: Self.score(8), why: "a good question", at: Self.at(10))
    let moods = Moods(base: base, conversations: [ConversationRef.main.tag: here])

    let felt = moods.felt(in: .main, at: Self.at(10))
    #expect(felt.word == "pleased")
    #expect(felt.valence.value == 7)
    #expect(felt.energy.value == 4)
    #expect(moods.felt(in: .item(Fixture.item), at: Self.at(10)).word == "low")
  }

  @Test func moodsFadeBackOverTheirSpans() {
    let base = BaseMood(
      mood: Mood(word: "elated", valence: Self.score(10), why: "shipped", at: Self.at(8)), energy: Self.score(9))
    let here = Mood(word: "annoyed", valence: Self.score(2), why: "ignored advice", at: Self.at(8))
    let moods = Moods(base: base, conversations: [ConversationRef.main.tag: here])

    let halfway = moods.felt(in: .main, at: Self.at(9))
    #expect(halfway.base.mood.valence.value == 9)
    #expect(halfway.here?.valence.value == 6)
    #expect(moods.felt(in: .main, at: Self.at(10)).here == nil)
    #expect(moods.felt(in: .main, at: Self.at(14)).base.mood.word == "cheerful")
    #expect(moods.pruned(at: Self.at(14)) == Moods())
  }

  @Test func aScoreInAFileIsReadAsTheNearestEnd() throws {
    #expect(try Fixture.decode([Score].self, "[-3, 4, 12]").map(\.value) == [0, 4, 10])
    #expect(Score(11) == nil)
  }
}
