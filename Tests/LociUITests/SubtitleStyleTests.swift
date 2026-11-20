import Foundation
import LociModel
import Testing

@testable import LociUI

/// S-S2, S-S4, S-S5: how subtitles look, kept on this Mac, and a podcast's sentence filling in.
struct SubtitleStyleTests {
  @Test func theStandardStyleIsBigYellowTranslationsOverWhiteOriginals() {
    let style = SubtitleStyle.standard
    #expect(style.preset == .big)
    #expect(style.translation == SubtitleStyle.Lettering(font: .pingFang, size: 23, color: .yellow, bold: true))
    #expect(style.original.color == .white)
    #expect(style.order == .translationAbove)
    #expect(style.lift == 6)
  }

  @Test func aPresetSetsTheTranslationsLettering() {
    var style = SubtitleStyle.standard
    style.choose(.glass)
    #expect(style.preset == .glass)
    #expect(style.translation.color == .white)
    #expect(!style.translation.bold)
    style.choose(.big)
    #expect(style.translation == SubtitleStyle.standard.translation)
  }

  @Test func sizeAndHeightStayWithinTheirRange() {
    var style = SubtitleStyle.standard
    style.raise(by: 100)
    style.translation.resize(by: -100)
    #expect(style.lift == 40)
    #expect(style.translation.size == 12)
  }

  @Test func theStyleSurvivesBeingStored() throws {
    var style = SubtitleStyle.standard
    style.choose(.band)
    style.original.font = .newYork
    style.order = .originalAbove
    style.lift = 12
    #expect(SubtitleStyle(rawValue: style.rawValue) == style)
    #expect(SubtitleStyle(rawValue: "not a style") == nil)
  }

  @Test func translationOnlyIsTheTranslationMode() {
    var mode = SubtitleMode.both
    var order = SubtitleStyle.BilingualOrder.translationAbove
    Bilingual.translationOnly.apply(to: &mode, &order)
    #expect(mode == .translation)
    #expect(Bilingual(mode: mode, order: order) == .translationOnly)
    Bilingual.originalAbove.apply(to: &mode, &order)
    #expect(mode == .both)
    #expect(order == .originalAbove)
  }

  @Test func bilingualOrderPutsTheTranslationFirstWhenAsked() {
    let lines = SubtitleMode.both.lines(of: "Hi", translated: "你好", order: .translationAbove)
    #expect(lines == [SubtitleLine(text: "你好", translated: true), SubtitleLine(text: "Hi", translated: false)])
  }

  @Test func aSentenceFillsInProportionToTimePlayed() throws {
    let segment = try Transcript.Segment(start: .seconds(10), end: .seconds(14), text: "abcdefgh")
    #expect(LyricFill.characters(of: segment, at: .seconds(9)) == 0)
    #expect(LyricFill.characters(of: segment, at: .seconds(11)) == 2)
    #expect(LyricFill.characters(of: segment, at: .seconds(14)) == 8)
  }
}
