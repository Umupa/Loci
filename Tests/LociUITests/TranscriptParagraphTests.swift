import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// E-S3, E-S5: an episode's transcript reads as paragraphs of talk.
@Suite struct TranscriptParagraphTests {
  /// Sentences of `seconds` each, one after another with no pause, said by `speakers` in turn.
  static func segments(
    _ texts: [String], every seconds: Int = 4, pauses: [Int: Int] = [:], speakers: [Int?]? = nil
  ) throws -> [Transcript.Segment] {
    var start = 0
    return try texts.enumerated().map { index, text in
      start += pauses[index] ?? 0
      defer { start += seconds }
      return try Transcript.Segment(
        start: .seconds(start), end: .seconds(start + seconds), text: text, speaker: speakers?[index] ?? nil)
    }
  }

  @Test func aChangeOfSpeakerStartsAParagraphHeadedByTheNewSpeaker() throws {
    let segments = try Self.segments(["Hi.", "Hello.", "So.", "Right."], speakers: [1, 2, 2, 1])
    let paragraphs = TranscriptParagraph.of(segments, chapters: [])
    #expect(paragraphs.map(\.sentences) == [0..<1, 1..<3, 3..<4])
    #expect(paragraphs.map(\.speaker) == [1, 2, 1])
    #expect(paragraphs.map(\.start) == [.zero, .seconds(4), .seconds(12)])
  }

  @MainActor @Test func aKnownSpeakerShowsByNameAndAnUnknownSpeakerByNumber() throws {
    let item = try SampleLibrary().podcast.id
    let known = SpeakerName(item: item, number: 1, name: "Maya Chen")
    let unknown = SpeakerName(item: item, number: 2, name: nil)

    #expect(known.label == Text(verbatim: "Maya Chen"))
    #expect(unknown.label == Text(joining: Text(.loci("transcript.speaker")), Text(verbatim: " 2")))
  }

  @MainActor @Test func everyParagraphByARenamedSpeakerRefreshesItsHeading() throws {
    let item = try SampleLibrary().podcast.id
    let segments = try Self.segments(["Hi.", "Hello.", "Right."], speakers: [1, 2, 1])
    let original = try Transcript(language: "en", origin: .platform, segments: segments, speakerNames: [1: "Maya"])
    let updated = try original.renamingSpeaker(1, to: "Maya Chen")

    func paragraphs(in transcript: Transcript) -> [EpisodeParagraph] {
      TranscriptParagraph.of(transcript.segments, chapters: []).map { paragraph in
        EpisodeParagraph(
          paragraph: paragraph, sentences: paragraph.sentences.map { ($0, transcript.segments[$0].text) },
          translation: nil,
          speaker: paragraph.speaker.map {
            SpeakerName(item: item, number: $0, name: transcript.name(ofSpeaker: $0))
          },
          playing: nil, chosen: nil, noted: [], space: "episode")
      }
    }

    #expect(zip(paragraphs(in: original), paragraphs(in: updated)).map { $0 != $1 } == [true, false, true])
  }

  @Test func aChapterStartsAParagraph() throws {
    let segments = try Self.segments(["One.", "Two.", "Three."])
    let chapters = [try Outline.Chapter(start: .seconds(8), title: "Later")]
    #expect(TranscriptParagraph.of(segments, chapters: chapters).map(\.sentences) == [0..<2, 2..<3])
  }

  @Test func aPauseStartsAParagraphOnlyOnceTheParagraphHasRunTwentySeconds() throws {
    let texts = (0..<9).map { "Sentence \($0)." }
    let segments = try Self.segments(texts, every: 5, pauses: [2: 2, 6: 2])
    #expect(TranscriptParagraph.of(segments, chapters: []).map(\.sentences) == [0..<6, 6..<9])
  }

  @Test func aLongTurnWithoutPausesBreaksAtTheEndOfASentence() throws {
    let texts = (0..<20).map { $0 == 14 ? "and then" : "Sentence \($0)." }
    let segments = try Self.segments(texts, every: 5)
    let paragraphs = TranscriptParagraph.of(segments, chapters: [])
    #expect(paragraphs.map(\.sentences) == [0..<16, 16..<20])
  }

  @Test func sentencesJoinWithSpacesExceptAfterChinese() {
    #expect(TranscriptParagraph.joined(["Hi.", "How are you?"]) == "Hi. How are you?")
    #expect(TranscriptParagraph.joined(["你好。", "最近怎么样？"]) == "你好。最近怎么样？")
    #expect(TranscriptParagraph.joined(["我们用 Kubernetes", "调度"]) == "我们用 Kubernetes 调度")
  }

  @Test func aParagraphsTranslationIsItsSentencesTranslationsJoined() throws {
    let transcript = try Transcript(
      language: "en", origin: .platform, segments: try Self.segments(["Hi.", "Bye."], speakers: [1, 1]))
    let readable = ReadableTranscript(
      transcript: transcript, translations: [try Translation(language: "zh-Hans", lines: ["你好。", "再见。"])],
      language: "zh-Hans")
    let paragraph = try #require(TranscriptParagraph.of(transcript.segments, chapters: []).first)
    #expect(paragraph.translation(in: readable) == "你好。再见。")
  }
}
