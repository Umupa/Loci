import Foundation
import Testing

@testable import LociModel

struct ImportChoiceTests {
  /// I-S3
  @Test func theFirstChoiceKeepsSevenTwentyPLocallyAndTranslatesIntoTheReadersLanguage() {
    let choice = ImportChoice.first(readerLanguage: "zh-Hans", speechModel: .small)

    #expect(choice.keeping == .local)
    #expect(choice.quality == .hd720)
    #expect(choice.siteSubtitles)
    #expect(choice.subtitleLanguage == nil)
    #expect(choice.recognition == ImportChoice.Recognizing(language: nil, model: .small))
    #expect(choice.translation == ImportChoice.Translating(language: "zh-Hans", runtime: nil))
  }

  @Test func aChoiceSurvivesJSON() throws {
    let choice = ImportChoice(
      keeping: .online, quality: .audio, siteSubtitles: false, subtitleLanguage: "ja",
      recognition: .init(language: "ja", model: .largeV3Turbo),
      translation: .init(language: "en", runtime: Runtime(provider: .codex, model: "gpt-5.2", effort: .low)))

    #expect(try Fixture.roundTrip(choice) == choice)
  }

  @Test func eachQualityHasItsHeight() {
    #expect(ImportChoice.Quality.allCases.map(\.height) == [1080, 720, nil])
  }
}
