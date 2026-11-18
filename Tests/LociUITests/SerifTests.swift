import AppKit
import CoreText
import SwiftUI
import Testing

@testable import LociUI

@MainActor
struct SerifTests {
  @Test func chineseAndItsPunctuationAreFoundAndLatinIsNot() {
    let text = "我叫 Loci，住在「这台」Mac 上。"
    let runs = Serif.cjkRuns(in: text).map { String(text[$0]) }

    #expect(runs == ["我叫", "，住在「这台」", "上。"])
  }

  /// Left to the system serif's fallback, `，` comes out half an em too wide.
  @Test func aFullWidthCommaInTheSerifIsOneEmWide() throws {
    let size: CGFloat = 15.5
    let text = NSMutableAttributedString(string: "Loci，住在", attributes: [.font: NSFont.serif(ofSize: size)])
    Serif.setCJKFonts(in: text)
    let line = CTLineCreateWithAttributedString(text)
    let runs = try #require(CTLineGetGlyphRuns(line) as? [CTRun])
    let comma = try #require(runs.first { CTRunGetStringRange($0).location == 4 })
    var advance = CGSize.zero
    CTRunGetAdvances(comma, CFRange(location: 0, length: 1), &advance)

    #expect(abs(advance.width - size) < 0.1)
  }

  @Test func theSerifKeepsItsWeightInSongti() throws {
    let text = NSMutableAttributedString(
      string: "标题", attributes: [.font: NSFont.serif(ofSize: 20, weight: .semibold)])
    Serif.setCJKFonts(in: text)

    #expect((text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "STSongti-SC-Bold")
  }

  @Test func chineseInSwiftUISerifTextIsSetInSongtiAndLatinInTheSerif() throws {
    let face = Serif.Face(size: 15.5)
    let attributed = Serif.attributed("Loci，住在", face)
    let fonts = attributed.runs.map(\.font)

    #expect(fonts == [face.latin, face.cjk])
  }

  @Test func aSemiboldSerifTakesSongtiBold() {
    #expect(Serif.Face(size: 17, weight: .semibold).cjk == Font.custom("STSongti-SC-Bold", size: 17))
  }

  @Test func markdownHeadingsKeepTheirStyleAndTheRestTakesTheSerif() throws {
    let face = Serif.Face(size: 15.5)
    let parsed = try SerifMarkdown(face: face).attributedString(for: "## 我是谁\n\n我叫 Loci。")
    let heading = parsed.runs.filter(Serif.isHeading)

    #expect(heading.allSatisfy { $0.font == nil })
    #expect(parsed.runs.contains { $0.font == face.cjk })
  }
}
