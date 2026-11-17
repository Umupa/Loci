import AppKit
import LociModel
import SwiftUI

/// The warm-night colors. Each one has its own value in dark and in light; neither is the other inverted.
///
/// Text colors are checked against the backgrounds they sit on, so every pair stays readable.
enum Palette {
  /// The content area.
  static let canvas = Color(nsColor: Tones.canvas)
  /// Panels beside the content, and the track of a segmented control. The sidebar uses the system material.
  static let raised = Color(nsColor: Tones.raised)
  /// Cards and input fields.
  static let surface = Color(nsColor: Tones.surface)
  static let ink = Color(nsColor: Tones.ink)
  static let inkMuted = Color(nsColor: Tones.inkMuted)
  static let line = Color(nsColor: Tones.line)
  /// Amber, for fills and marks. Use `accentInk` when amber is the color of text.
  static let accent = Color(nsColor: Tones.accent)
  static let accentInk = Color(nsColor: Tones.accentInk)
  /// Text on an amber fill.
  static let onAccent = Color(nsColor: Tones.onAccent)
  static let selection = Color(nsColor: Tones.selection)
  static let onSelection = Color(nsColor: Tones.onSelection)

  /// The pairs of text and background the interface uses, for checking contrast.
  static let readablePairs: [(text: Color, background: Color, name: String)] = [
    (ink, canvas, "ink on canvas"), (ink, surface, "ink on surface"), (ink, raised, "ink on raised"),
    (inkMuted, canvas, "muted on canvas"), (inkMuted, surface, "muted on surface"),
    (inkMuted, raised, "muted on raised"),
    (accentInk, canvas, "amber text on canvas"), (accentInk, raised, "amber text on raised"),
    (onAccent, accent, "text on amber"), (onSelection, selection, "selected text"),
  ]
}

/// The same colors for AppKit, which draws the reader's text.
enum Tones {
  static let canvas = NSColor(dark: 0x0D0C0B, light: 0xFBFAF7)
  static let raised = NSColor(dark: 0x171513, light: 0xF1EEE8)
  static let surface = NSColor(dark: 0x191714, light: 0xFFFFFF)
  static let ink = NSColor(dark: 0xF2EEE6, light: 0x1B1916)
  static let inkMuted = NSColor(dark: 0x8C867B, light: 0x6F6A61)
  static let line = NSColor(dark: 0x2A2622, light: 0xE4DFD6)
  static let accent = NSColor(dark: 0xEBA53A, light: 0xD98E1F)
  static let accentInk = NSColor(dark: 0xEBA53A, light: 0x9A5F0A)
  static let onAccent = NSColor(dark: 0x1A1206, light: 0x1A1206)
  static let selection = NSColor(dark: 0x3A2D17, light: 0xF3DDB0)
  static let onSelection = NSColor(dark: 0xF5D9A0, light: 0x1B1916)
}

extension Color {
  init(dark: UInt32, light: UInt32) {
    self.init(nsColor: NSColor(dark: dark, light: light))
  }
}

extension NSColor {
  /// A color that follows the appearance it is drawn in, for text drawn by AppKit.
  convenience init(dark: UInt32, light: UInt32) {
    self.init(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return NSColor(rgb: isDark ? dark : light)
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
