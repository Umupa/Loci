import AppKit
import SwiftUI

/// How books are set: size, line spacing and face. One setting for every book, kept in the app's preferences.
struct BookSettings: Hashable {
  var size: Int
  var spacing: Spacing
  var face: Face

  static let sizes = 14...28
  static let standard = BookSettings(size: 18, spacing: .normal, face: .serif)

  enum Spacing: String, CaseIterable {
    case tight, normal, loose

    var lineHeight: Double {
      switch self {
      case .tight: 1.6
      case .normal: 1.85
      case .loose: 2.1
      }
    }

    var name: LocalizedStringResource {
      switch self {
      case .tight: .loci("book.spacingTight")
      case .normal: .loci("book.spacingNormal")
      case .loose: .loci("book.spacingLoose")
      }
    }
  }

  enum Face: String, CaseIterable {
    case serif, sans

    var family: String {
      switch self {
      case .serif: #"ui-serif, "Songti SC", serif"#
      case .sans: #"system-ui, "PingFang SC", sans-serif"#
      }
    }

    var name: LocalizedStringResource {
      switch self {
      case .serif: .loci("book.faceSerif")
      case .sans: .loci("book.faceSans")
      }
    }
  }

  static let sizeKey = "bookSize"
  static let spacingKey = "bookSpacing"
  static let faceKey = "bookFace"
}

/// Everything that decides where the lines of a book fall on its pages.
struct BookLayout: Hashable {
  var settings: BookSettings
  var dark: Bool
  var width: Double

  /// Two pages side by side once a window is wide enough for two comfortable columns.
  static let twoPagesFrom = 960.0
  static let top = 56.0

  var columns: Int { width >= Self.twoPagesFrom ? 2 : 1 }
  var margin: Double { columns == 2 ? 72 : 48 }

  var css: String {
    let paper = Self.hex(Tones.canvas, dark: dark)
    let ink = Self.hex(Tones.ink, dark: dark)
    let muted = Self.hex(Tones.inkMuted, dark: dark)
    let well = Self.hex(Tones.well, dark: dark)
    let face = settings.face.family
    return """
      :root { color-scheme: \(dark ? "dark" : "light"); }
      html { height: 100vh; overflow: hidden; background: \(paper) !important; }
      body { background: \(paper) !important; color: \(ink) !important; margin: 0 !important;
        height: calc(100vh - \(Self.top * 2)px) !important; padding: \(Self.top)px \(margin)px !important;
        box-sizing: content-box !important; column-count: \(columns) !important; column-gap: \(margin * 2)px !important;
        column-fill: auto !important; font-size: \(settings.size)px !important;
        line-height: \(settings.spacing.lineHeight) !important; -webkit-font-smoothing: antialiased;
        hanging-punctuation: allow-end; overflow-wrap: break-word; }
      body * { background: transparent !important; color: inherit !important; border-color: \(muted)55 !important;
        max-width: 100%; }
      body, body * { font-family: \(face) !important; }
      p { margin: 0 0 0.6em 0 !important; }
      :lang(zh) p, :lang(ja) p { text-align: justify !important; text-indent: 2em; }
      h1, h2, h3, h4, h5, h6 { font-weight: 600 !important; line-height: 1.35 !important; margin: 1.2em 0 0.8em !important;
        text-indent: 0 !important; break-after: avoid; }
      h1 { font-size: 1.6em !important; } h2 { font-size: 1.35em !important; } h3 { font-size: 1.15em !important; }
      img, svg { max-width: 100% !important; max-height: calc(100vh - \(Self.top * 2 + 8)px) !important;
        height: auto !important; object-fit: contain; break-inside: avoid; }
      img { background: #FCFBF8 !important; border-radius: 3px; }
      pre, code, kbd, tt, pre * { font-family: ui-monospace, "SF Mono", Menlo, monospace !important; }
      pre, code, kbd, tt { font-size: 0.82em !important; }
      pre { background: \(well) !important; padding: 12px 14px !important; border-radius: 8px; white-space: pre-wrap;
        text-indent: 0 !important; line-height: 1.5 !important; }
      table { border-collapse: collapse; break-inside: avoid; }
      th, td { padding: 4px 8px; text-indent: 0 !important; }
      blockquote { margin: 1em 0 !important; padding-left: 1em !important; border-left: 2px solid \(muted)88 !important; }
      a { color: inherit !important; text-decoration-color: \(muted) !important; }
      sup, sub { line-height: 0 !important; }
      hr { border: 0 !important; border-top: 1px solid \(muted)66 !important; }
      """
  }

  static func hex(_ color: NSColor, dark: Bool) -> String {
    var hex = "#000000"
    NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
      guard let rgb = color.usingColorSpace(.sRGB) else { return }
      let parts = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
      hex = "#" + parts.map { String(format: "%02X", $0) }.joined()
    }
    return hex
  }
}
