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
}
