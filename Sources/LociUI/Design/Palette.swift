import AppKit
import LociModel
import SwiftUI

/// The warm colors. Each one has its own value in dark and in light; neither is the other inverted.
///
/// Text colors are checked against the backgrounds they sit on, so every pair stays readable.
enum Palette {
  /// The content area.
  static let canvas = Color(nsColor: Tones.canvas)
  /// The panel beside the text, and code blocks.
  static let well = Color(nsColor: Tones.well)
  /// Under the sidebar's glass: warm at the top, cooling toward the bottom, as the design's wallpaper shows
  /// through it.
  static let sidebarWash = LinearGradient(
    stops: [
      .init(color: Color(nsColor: Tones.sidebarTop), location: 0.15),
      .init(color: Color(nsColor: Tones.sidebarMiddle), location: 0.55),
      .init(color: Color(nsColor: Tones.sidebarBottom), location: 0.85),
    ],
    startPoint: .top, endPoint: .bottom)
  /// Cards and input fields.
  static let surface = Color(nsColor: Tones.surface)
  static let ink = Color(nsColor: Tones.ink)
  static let inkMuted = Color(nsColor: Tones.inkMuted)
  /// Muted text in the sidebar, a little darker in light so it stays readable where the sidebar is grayest.
  static let sidebarInkMuted = Color(nsColor: Tones.sidebarInkMuted)
  /// Section labels, glyphs and lessons not yet written; never for text that must be read.
  static let inkFaint = Color(nsColor: Tones.inkFaint)
  /// Hairlines between things and around cards.
  static let line = Color(nsColor: Tones.line)
  /// Hairlines that must show on a card, such as between rows of a group.
  static let lineStrong = Color(nsColor: Tones.lineStrong)
  /// Behind a row under the pointer.
  static let fill = Color(nsColor: Tones.fill)
  /// The track of a segmented control, and behind a button under the pointer.
  static let fillStrong = Color(nsColor: Tones.fillStrong)
  /// Amber, for fills and marks. Use `accentInk` when amber is the color of text.
  static let accent = Color(nsColor: Tones.accent)
  static let accentInk = Color(nsColor: Tones.accentInk)
  /// Text on an amber fill.
  static let onAccent = Color(nsColor: Tones.onAccent)
  /// Behind what is selected: a wash of amber, never a solid block.
  static let tint = Color(nsColor: Tones.tint)
  /// Behind text selected in the reader: a wash of ink, so it never reads as a highlight.
  static let selection = Color(nsColor: Tones.selection)
  /// Under the words of a highlight.
  static let mark = Color(nsColor: Tones.mark)
  /// Over a passage or card just jumped to, fading out.
  static let flash = Color(nsColor: Tones.flash)
  /// A thing that is ready to use, such as an installed agent.
  static let ready = Color(nsColor: Tones.ready)
  /// The thumb of a segmented control and the face of a push button.
  static let thumb = Color(nsColor: Tones.thumb)
  /// Behind a paragraph the mentor changed since the reader last saw it. Fainter than a selection.
  static let revised = Color(nsColor: Tones.revised)

  /// Behind a cover while it loads, and under a player.
  static let coverBackdrop = Color(nsColor: Tones.coverBackdrop)
  /// Words over a cover or a picture, the same in light and dark because the picture is.
  static let onCover = Color(nsColor: NSColor(rgb: 0xFFF6EA))
  static let onCoverMuted = Color(nsColor: NSColor(rgb: 0xFFF0E0)).opacity(0.7)
  /// The dark wash a cover's title sits on.
  static let coverShade = Color(nsColor: NSColor(rgb: 0x0E0A07))
  /// Menus and bars that float over the page.
  static let floating = Color(nsColor: Tones.floating)

  /// Code, colored by what each word is. Code sits on `well`.
  enum Code {
    static let keyword = Color(nsColor: Tones.codeKeyword)
    static let string = Color(nsColor: Tones.codeString)
    static let number = Color(nsColor: Tones.codeNumber)
    static let name = Color(nsColor: Tones.codeName)
  }

  /// The pairs of text and background the interface uses, for checking contrast.
  static let readablePairs: [(text: Color, background: Color, name: String)] = [
    (ink, canvas, "ink on canvas"), (ink, surface, "ink on surface"), (ink, well, "ink on well"),
    (ink, Color(nsColor: Tones.sidebarTop), "ink on the sidebar's top"),
    (ink, Color(nsColor: Tones.sidebarBottom), "ink on the sidebar's bottom"),
    (sidebarInkMuted, Color(nsColor: Tones.sidebarTop), "muted on the sidebar's top"),
    (sidebarInkMuted, Color(nsColor: Tones.sidebarBottom), "muted on the sidebar's bottom"),
    (ink, tint, "selected text"), (ink, selection, "text selected in the reader"), (ink, mark, "highlighted text"),
    (inkMuted, canvas, "muted on canvas"), (inkMuted, surface, "muted on surface"),
    (accentInk, canvas, "amber text on canvas"), (accentInk, surface, "amber text on surface"),
    (onAccent, accent, "text on amber"), (ink, revised, "revised text"),
    (Code.keyword, well, "code keyword"), (Code.string, well, "code string"),
    (Code.number, well, "code number"), (Code.name, well, "code name"),
  ]
}

/// The same colors for AppKit, which draws the reader's text.
enum Tones {
  static let canvas = NSColor(dark: 0x121110, light: 0xFCFBF8)
  static let well = NSColor(dark: 0x191715, light: 0xF6F3EE)
  static let surface = NSColor(dark: 0x1E1C19, light: 0xFFFFFF)
  static let sidebarTop = NSColor(dark: 0x2F2419, light: 0xF5ECDE)
  static let sidebarMiddle = NSColor(dark: 0x201B17, light: 0xE7DCCF)
  static let sidebarBottom = NSColor(dark: 0x1A1817, light: 0xD6D2CF)
  static let sidebarInkMuted = NSColor(dark: 0x9A968F, light: 0x5D5A56)
  static let ink = NSColor(dark: 0xF2EEE6, light: 0x1D1B18)
  static let inkMuted = NSColor(dark: 0x9A968F, light: 0x6E6B66)
  static let inkFaint = NSColor(dark: 0x5E5C59, light: 0xACAAA7)
  static let line = NSColor(dark: 0xFFF5E6, light: 0x1D1B18, alpha: (dark: 0.08, light: 0.09))
  static let lineStrong = NSColor(dark: 0xFFF5E6, light: 0x1D1B18, alpha: (dark: 0.13, light: 0.14))
  static let fill = NSColor(dark: 0xFFF5E6, light: 0x1D1B18, alpha: (dark: 0.05, light: 0.045))
  static let fillStrong = NSColor(dark: 0xFFF5E6, light: 0x1D1B18, alpha: (dark: 0.09, light: 0.08))
  static let accent = NSColor(dark: 0xEBA53A, light: 0xD98E1F)
  static let accentInk = NSColor(dark: 0xF3D9AE, light: 0x94590A)
  static let onAccent = NSColor(dark: 0x1A1206, light: 0x1A1206)
  static let tint = NSColor(dark: 0xEBA53A, light: 0xD98E1F, alpha: (dark: 0.17, light: 0.15))
  static let selection = NSColor(dark: 0xFFF5E6, light: 0x1D1B18, alpha: (dark: 0.16, light: 0.11))
  static let mark = NSColor(dark: 0xEBA53A, light: 0xD98E1F, alpha: (dark: 0.30, light: 0.26))
  static let flash = NSColor(dark: 0xEBA53A, light: 0xD98E1F, alpha: (dark: 0.6, light: 0.6))
  static let ready = NSColor(dark: 0x6CC783, light: 0x34A853)
  static let thumb = NSColor(dark: 0x5A544D, light: 0xFFFFFF)
  static let revised = NSColor(dark: 0x241C10, light: 0xFAEDD3)
  static let coverBackdrop = NSColor(dark: 0x2A2420, light: 0x2A2420)
  static let floating = NSColor(dark: 0x2C2824, light: 0xFDFBF8, alpha: (dark: 0.96, light: 0.96))
  static let codeKeyword = NSColor(dark: 0xE09A6A, light: 0x9C4524)
  static let codeString = NSColor(dark: 0xA9C27C, light: 0x4F6A22)
  static let codeNumber = NSColor(dark: 0xDDB86E, light: 0x7E5600)
  static let codeName = NSColor(dark: 0x93B9CC, light: 0x2C5F78)
}

extension Color {
  init(dark: UInt32, light: UInt32) {
    self.init(nsColor: NSColor(dark: dark, light: light))
  }
}

extension NSColor {
  /// A color that follows the appearance it is drawn in, for text drawn by AppKit.
  convenience init(dark: UInt32, light: UInt32, alpha: (dark: CGFloat, light: CGFloat) = (1, 1)) {
    self.init(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return NSColor(rgb: isDark ? dark : light).withAlphaComponent(isDark ? alpha.dark : alpha.light)
    }
  }
}

extension NSColor {
  convenience init(rgb: UInt32) {
    self.init(
      srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
  }
}

extension MentorColor {
  var color: Color {
    Color(nsColor: NSColor(rgb: UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)))
  }
}
