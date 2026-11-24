import AppKit
import SwiftUI

/// The menu bar icon: the app icon's two leaning cards in outline, drawn as a template so it takes the menu
/// bar's color. While the companion works, the card behind fills in.
public struct MenuBarGlyph: View {
  let companion: MenuBarCompanion

  public init(companion: MenuBarCompanion) {
    self.companion = companion
  }

  public var body: some View {
    Image(nsImage: Self.image(working: companion.work != nil))
      .accessibilityLabel(Text(.loci("companion.title")))
  }

  static func image(working: Bool) -> NSImage {
    let image = NSImage(size: size, flipped: false) { _ in
      let back = card(center: CGPoint(x: 7.6, y: 9.3), degrees: 9)
      let front = card(center: CGPoint(x: 10.6, y: 8.6), degrees: -3)
      NSColor.black.set()
      if working { back.fill() } else { back.stroke() }
      NSGraphicsContext.current?.compositingOperation = .clear
      front.fill()
      NSGraphicsContext.current?.compositingOperation = .sourceOver
      front.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }

  private static let size = NSSize(width: 18, height: 18)

  private static func card(center: CGPoint, degrees: CGFloat) -> NSBezierPath {
    let path = NSBezierPath(
      roundedRect: NSRect(x: -4.6, y: -6, width: 9.2, height: 12), xRadius: 1.8, yRadius: 1.8)
    path.lineWidth = 1.3
    var turn = AffineTransform(rotationByDegrees: degrees)
    turn.append(AffineTransform(translationByX: center.x, byY: center.y))
    path.transform(using: turn)
    return path
  }
}
