import AppKit
import Foundation
import LociModel
import Testing

@testable import LociUI

/// DS-S8–DS-S12: how chart rows write numbers, and how heat tiles share their space.
struct ChartFigureTests {
  @Test func changesAreSignedWithATrueMinusAndNumbersGroupTheSameInEitherLanguage() {
    #expect(PanelFigures.change(0.0118) == "+1.18%")
    #expect(PanelFigures.change(-0.0186) == "−1.86%")
    #expect(PanelFigures.change(0.00001) == "0.00%")
    #expect(PanelFigures.change(nil) == "—")
    #expect(PanelFigures.number(20_912, style: PanelStyle(digits: 0)) == "20,912")
    #expect(PanelFigures.number(0.159, style: PanelStyle(format: .percent)) == "15.90%")
    #expect(PanelFigures.number(61.8, style: PanelStyle(digits: 1, unit: "万")) == "61.8 万")
    #expect(PanelFigures.number(-3.5, style: PanelStyle()) == "−3.50")
    #expect(PanelFigures.number(nil, style: PanelStyle()) == "—")
  }

  @Test func upIsRedDownIsGreenAndNothingIsInk() {
    #expect(PanelFigures.tone(0.01) == Palette.rise)
    #expect(PanelFigures.tone(-0.01) == Palette.fall)
    #expect(PanelFigures.tone(0) == Palette.ink)
    #expect(PanelFigures.tone(nil) == Palette.ink)
  }

  @Test func eachTileTakesTheShareOfTheSpaceItsWeightIs() {
    let size = CGSize(width: 340, height: 150)
    let weights = [8.0, 6, 5, 4, 3.5, 3, 2.6, 2.2, 1.2, 1]

    let tiles = HeatLayout.tiles(weights, in: size)

    let total = weights.reduce(0, +)
    for (tile, weight) in zip(tiles, weights) {
      #expect(abs(Double(tile.width * tile.height) - weight / total * Double(size.width * size.height)) < 1)
      #expect(CGRect(origin: .zero, size: size).insetBy(dx: -0.01, dy: -0.01).contains(tile))
    }
    for (index, tile) in tiles.enumerated() {
      for other in tiles[(index + 1)...] {
        #expect(tile.intersection(other).width * tile.intersection(other).height < 0.01)
      }
    }
  }

  @Test func aTileWithNoWeightGetsNoSpace() {
    let tiles = HeatLayout.tiles([1, 0, -2, 1], in: CGSize(width: 100, height: 50))

    #expect(tiles[1] == .zero && tiles[2] == .zero)
    #expect(tiles[0].width * tiles[0].height == 2500)
  }

  @Test func aQuotesFiguresRollOnTheirPriceOrChangeAndNotWhenMotionIsReduced() {
    #expect(PanelQuotes.Figures(price: 1.873, change: 0.01) != PanelQuotes.Figures(price: 1.874, change: 0.01))
    #expect(PanelQuotes.Figures(price: 1.873, change: 0.01) != PanelQuotes.Figures(price: 1.873, change: 0.02))
    #expect(PanelQuotes.motion(reducesMotion: true) == nil)
    #expect(PanelQuotes.motion(reducesMotion: false) != nil)
  }

  @Test func zoneStopsAreWrittenWithoutNeedlessDigits() {
    let percent = PanelStyle(format: .percent, digits: 1)

    #expect([0, 0.03, 0.1, 0.2].map { PanelFigures.stop($0, style: percent) } == ["0", "3%", "10%", "20%"])
    #expect(PanelFigures.stop(0.125, style: percent) == "12.5%")
    #expect(PanelFigures.stop(1500, style: PanelStyle(unit: "元")) == "1,500 元")
  }

  @Test func stopsTooCloseToReadAreLeftOutKeepingTheEnds() {
    let shown = PanelZonesView.shownStops(centers: [0, 12, 40, 80, 82, 200], widths: [8, 18, 22, 22, 22, 22])

    #expect(shown == [0, 2, 3, 5])
    #expect(PanelZonesView.shownStops(centers: [0, 40, 100], widths: [8, 16, 18]) == [0, 1, 2])
  }

  @Test func aNarrowTilesCodeIsWrittenSmallerOrUpwardButNeverCut() {
    let roomy = PanelHeat.fit("NVDA", in: CGSize(width: 120, height: 80))
    let narrow = PanelHeat.fit("HC07", in: CGSize(width: 30, height: 60))
    let slim = PanelHeat.fit("HC08", in: CGSize(width: 14, height: 70))

    #expect(roomy == PanelHeat.Fit(size: 12, upward: false))
    #expect(!narrow.upward && narrow.size < 10.5 && narrow.size >= PanelHeat.smallest)
    #expect(PanelHeat.width(of: "HC07", size: narrow.size) <= 30 - 2 * PanelHeat.inset)
    #expect(slim.upward && PanelHeat.width(of: "HC08", size: slim.size) <= 70 - 2 * PanelHeat.inset)
    let short = PanelHeat.fit("HC08", in: CGSize(width: 34, height: 18))
    #expect(!short.upward && short.size * PanelHeat.lineHeight <= 18 - 2 * PanelHeat.inset)
  }

  @Test func aChangesBlockInTheDarkIsAsSoftAsTheDesigns() {
    let dark = NSAppearance(named: .darkAqua)
    func hex(_ color: NSColor) -> UInt32 {
      var resolved = color
      dark?.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) ?? color }
      return UInt32((resolved.redComponent * 255).rounded()) << 16 | UInt32((resolved.greenComponent * 255).rounded())
        << 8
        | UInt32((resolved.blueComponent * 255).rounded())
    }

    #expect(hex(Palette.riseBlockColor) == 0xE78472)
    #expect(hex(Palette.fallBlockColor) == 0x74C296)
  }
}
