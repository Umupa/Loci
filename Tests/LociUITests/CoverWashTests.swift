import AppKit
import LociModel
import Testing

@testable import LociUI

@MainActor
struct CoverWashTests {
  @Test func aSquareCoversWashBlursAwayItsLettering() throws {
    let cover = NSImage(size: NSSize(width: 400, height: 400), flipped: false) { rect in
      NSColor.black.setFill()
      rect.fill()
      NSColor.white.setFill()
      NSRect(x: 0, y: 0, width: 200, height: 400).fill()
      return true
    }
    let wash = try #require(CoverWash.of(cover))
    let bitmap = NSBitmapImageRep(cgImage: try #require(wash.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    let middle = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
    let brightness = middle.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
    #expect(brightness > 0.15 && brightness < 0.85)
    #expect(bitmap.pixelsWide <= 96)
  }

  @Test func aCoverChosenByHandGetsItsWashAtOnce() {
    let covers = Covers()
    let cover = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
      NSColor.orange.setFill()
      rect.fill()
      return true
    }
    let item = EntityID()
    covers.replace(item, with: cover)
    #expect(covers.wash(of: item) != nil)
  }
}
