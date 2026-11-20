import Foundation
import LociModel
import Testing

@testable import LociUI

/// I-S2, I-S3: what the import panel's choices add up to.
struct ImportDraftTests {
  static let first = ImportChoice.first(readerLanguage: "zh-Hans", speechModel: .small)

  @Test func aSiteWithSubtitlesUsesThemAndLeavesRecognitionOff() {
    let draft = ImportDraft(
      Self.first, offered: ["en", "ja"], spoken: "en", speechModel: .small, readerLanguage: "zh-Hans")

    #expect(draft.subtitles)
    #expect(!draft.recognizes)
    #expect(draft.subtitleLanguage == "en")
  }

  @Test func aSiteWithoutSubtitlesTurnsRecognitionOn() {
    var choice = Self.first
    choice.recognition = nil

    let draft = ImportDraft(choice, speechModel: .small, readerLanguage: "zh-Hans")

    #expect(!draft.subtitles)
    #expect(draft.recognizes)
  }

  @Test func subtitlesAndRecognitionTakeTurns() {
    var draft = ImportDraft(Self.first, offered: ["en"], spoken: "en", speechModel: .small, readerLanguage: "zh-Hans")

    draft.recognize(true)
    #expect(!draft.subtitles)
    draft.useSubtitles(true)
    #expect(!draft.recognizes)
    draft.useSubtitles(false)
    #expect(draft.recognizes)
  }

  @Test func theLanguageChosenBeforeIsKeptWhenTheSiteHasIt() {
    var choice = Self.first
    choice.subtitleLanguage = "ja"

    #expect(
      ImportDraft(choice, offered: ["en", "ja"], spoken: "en", speechModel: .small, readerLanguage: "en")
        .subtitleLanguage == "ja")
    #expect(
      ImportDraft(choice, offered: ["en"], spoken: "en", speechModel: .small, readerLanguage: "en")
        .subtitleLanguage == "en")
  }

  @Test func turningEverythingOffTakesNoTranscriptAndNoTranslation() {
    var draft = ImportDraft(Self.first, offered: ["en"], spoken: "en", speechModel: .small, readerLanguage: "zh-Hans")

    draft.useSubtitles(false)
    draft.recognize(false)
    draft.translates = false

    #expect(draft.choice.recognition == nil)
    #expect(draft.choice.translation == nil)
    #expect(!draft.choice.siteSubtitles)
  }

  @Test func withoutSubtitlesToChooseTheLastSayAboutThemIsKept() {
    var draft = ImportDraft(Self.first, speechModel: .small, readerLanguage: "zh-Hans")
    draft.recognize(false)

    #expect(draft.choice.siteSubtitles)
    #expect(draft.choice.recognition == nil)
  }

  @Test func theSpaceUsedFollowsTheQualityAndNothingIsKeptOnline() {
    let sizes: [ImportChoice.Quality: Int64] = [.hd1080: 400, .hd720: 200, .audio: 15]
    var draft = ImportDraft(Self.first, offered: ["en"], spoken: "en", speechModel: .small, readerLanguage: "zh-Hans")

    #expect(draft.bytes(sizes: sizes, isAudio: false, missingModel: true) == 200)
    draft.quality = .hd1080
    #expect(draft.bytes(sizes: sizes, isAudio: false, missingModel: false) == 400)
    #expect(draft.bytes(sizes: sizes, isAudio: true, missingModel: false) == 15)
    draft.recognize(true)
    #expect(draft.bytes(sizes: sizes, isAudio: false, missingModel: true) == 400 + SpeechModel.small.size)
    draft.keeping = .online
    #expect(draft.bytes(sizes: sizes, isAudio: false, missingModel: false) == 0)
    draft.keeping = .local
    #expect(draft.bytes(sizes: [:], isAudio: false, missingModel: false) == nil)
  }
}
