import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// α1-S9: no text is hard to read, in either appearance.
@MainActor
struct PaletteTests {
  /// The color composited over its surface in the given appearance.
  static func components(
    of color: Color, in appearance: NSAppearance.Name, over surface: NSColor = Tones.canvas
  ) -> [Double] {
    var components: [Double] = []
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
      guard let resolved = NSColor(color).usingColorSpace(.sRGB),
        let base = surface.usingColorSpace(.sRGB)
      else { return }
      let alpha = resolved.alphaComponent
      components = zip(
        [resolved.redComponent, resolved.greenComponent, resolved.blueComponent],
        [base.redComponent, base.greenComponent, base.blueComponent]
      ).map { Double($0 * alpha + $1 * (1 - alpha)) }
    }
    return components
  }

  static func alpha(of color: Color, in appearance: NSAppearance.Name) -> Double {
    var alpha = 1.0
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
      alpha = Double(NSColor(color).usingColorSpace(.sRGB)?.alphaComponent ?? 1)
    }
    return alpha
  }

  /// WCAG relative luminance contrast, from 1 (none) to 21.
  static func contrast(_ first: [Double], _ second: [Double]) -> Double {
    func luminance(_ rgb: [Double]) -> Double {
      let linear = rgb.map { $0 <= 0.039_28 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
      return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
    let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
    return (lighter + 0.05) / (darker + 0.05)
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func everyTextColorIsReadableOnItsBackground(appearance: NSAppearance.Name) {
    for pair in Palette.readablePairs {
      let text = Self.components(of: pair.text, in: appearance)
      let background = Self.components(of: pair.background, in: appearance)
      let ratio = Self.contrast(text, background)
      #expect(ratio >= 4.5, "\(pair.name) in \(appearance.rawValue) is \(ratio)")
    }
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theSelectedSidebarSymbolIsReadableAnywhereInTheSidebar(appearance: NSAppearance.Name) {
    let symbol = Self.components(of: Palette.sidebarSelectedInk, in: appearance)
    for surface in [Tones.sidebarTop, Tones.sidebarMiddle, Tones.sidebarBottom] {
      let background = Self.components(of: Palette.tint, in: appearance, over: surface)
      #expect(Self.contrast(symbol, background) >= 4.5)
    }
  }

  @Test func eachColorHasItsOwnDarkValue() {
    let canvas = (Self.components(of: Palette.canvas, in: .aqua), Self.components(of: Palette.canvas, in: .darkAqua))

    #expect(canvas.0 != canvas.1)
    #expect(canvas.1.allSatisfy { $0 < 0.1 })
  }

  /// What is selected is washed in amber, not filled with it.
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func aSelectionIsAWashOfAmber(appearance: NSAppearance.Name) {
    #expect(Self.alpha(of: Palette.tint, in: appearance) < 0.2)
    #expect(Self.alpha(of: Palette.mark, in: appearance) < 0.35)
  }
}
