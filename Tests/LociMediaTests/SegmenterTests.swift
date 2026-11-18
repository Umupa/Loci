import Foundation
import LociModel
import Testing

@testable import LociMedia

struct SegmenterTests {
  /// Words a quarter second apart, with longer pauses where `pauses` says.
  static func words(_ text: String, pauses: [Int: Double] = [:], dense: Bool = false) -> [SpokenWord] {
    let pieces = dense ? text.map { String($0) } : text.split(separator: " ").map { " " + $0 }
    var time = 0.0
    return pieces.enumerated().map { index, piece in
      time += pauses[index] ?? 0
      defer { time += 0.25 }
      return SpokenWord(
        text: piece, start: .milliseconds(Int(time * 1000)), end: .milliseconds(Int((time + 0.2) * 1000)))
    }
  }

  @Test func sentencesEndWhereTheLanguageSaysTheyEnd() {
    let segments = Segmenter().segments(Self.words("The scheduler filters nodes. Then it scores them."))

    #expect(segments.map(\.text) == ["The scheduler filters nodes.", "Then it scores them."])
    #expect(segments[1].start == .milliseconds(1000))
    #expect(segments[0].end == .milliseconds(950))
  }

  @Test func aLongSentenceIsCutWhereTheSpeakerPaused() {
    let text =
      "when the cluster is busy the scheduler looks at every node it knows about and then it picks the one that leaves the most room for the next pod to land"
    let pauseBeforeAnd = text.split(separator: " ").firstIndex(of: "and")!

    let segments = Segmenter().segments(Self.words(text, pauses: [pauseBeforeAnd: 1.2]))

    #expect(segments.count >= 2)
    #expect(segments.first?.text.hasSuffix("knows about") == true)
    #expect(segments.allSatisfy { $0.text.count <= 84 })
  }

  @Test func aLongSentenceWithoutPausesIsCutAtAClauseMark() {
    let text =
      "Kubernetes keeps a queue of pods waiting for a place to run, and the scheduler takes them one at a time in order of priority"

    let segments = Segmenter().segments(Self.words(text))

    #expect(
      segments.map(\.text) == [
        "Kubernetes keeps a queue of pods waiting for a place to run,",
        "and the scheduler takes them one at a time in order of priority",
      ])
  }

  @Test func chineseIsMeasuredInCharactersAndCutBetweenWords() {
    let text = "调度器先过滤掉放不下这个容器的节点然后给剩下的每一个节点打分最后选出分数最高的那一个节点来运行它"

    let segments = Segmenter().segments(Self.words(text, dense: true))

    #expect(segments.count >= 2)
    #expect(segments.allSatisfy { $0.text.count <= 36 })
    #expect(segments.map(\.text).joined() == text)
    #expect(!segments.contains { $0.text.hasSuffix("节") })
  }

  @Test func theSentenceStillBeingSpokenWaitsForMoreWords() {
    let (segments, rest) = Segmenter().finished(Self.words("One done. Two is still"))

    #expect(segments.map(\.text) == ["One done."])
    #expect(rest.map(\.text).joined() == " Two is still")
  }

  @Test func blankWordsAreIgnored() {
    #expect(Segmenter().segments([SpokenWord(text: " ", start: .zero, end: .seconds(1))]).isEmpty)
  }

  @Test func tokensJoinIntoWordsAndCharactersSplitAcrossTokensWaitForTheirLastByte() {
    var joiner = WordJoiner()
    let ni = Array("你".utf8)
    joiner.add(Array(" Hel".utf8), start: .zero, end: .milliseconds(100))
    joiner.add(Array("lo".utf8), start: .milliseconds(100), end: .milliseconds(200))
    joiner.add(Array(",".utf8), start: .milliseconds(200), end: .milliseconds(210))
    joiner.add(Array(ni.prefix(2)), start: .milliseconds(300), end: .milliseconds(350))
    joiner.add(Array(ni.suffix(1)) + Array("好".utf8), start: .milliseconds(350), end: .milliseconds(400))
    joiner.add(Array("吗".utf8), start: .milliseconds(400), end: .milliseconds(500))

    let words = joiner.finish()

    #expect(words.map(\.text) == [" Hello,", "你好", "吗"])
    #expect(words.first?.end == .milliseconds(210))
    #expect(words[1].start == .milliseconds(300))
  }
}
