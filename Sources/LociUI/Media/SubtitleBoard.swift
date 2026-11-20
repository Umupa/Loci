import AppKit
import SwiftUI

/// The style as it looks on three kinds of picture: a light one, a dark one and a busy one.
struct SubtitleBoard: View {
  @Environment(\.locale) private var locale
  let style: SubtitleStyle
  let mode: SubtitleMode

  var body: some View {
    HStack(spacing: 6) {
      ForEach(Backdrop.allCases, id: \.self) { backdrop in
        backdrop.picture
          .aspectRatio(16 / 10, contentMode: .fit)
          .overlay {
            SubtitleOverlay(lines: lines, style: style, referenceWidth: 300)
          }
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(
              Palette.lineStrong, lineWidth: Size.hairline)
          )
      }
    }
    .accessibilityHidden(true)
  }

  private var lines: [SubtitleLine] {
    mode.lines(
      of: KeyPointWords.string(.loci("caption.sampleOriginal"), in: locale),
      translated: KeyPointWords.string(.loci("caption.sampleTranslation"), in: locale), order: style.order)
  }

  private enum Backdrop: CaseIterable {
    case light, dark, busy

    @ViewBuilder var picture: some View {
      switch self {
      case .light:
        LinearGradient(
          colors: [Color(nsColor: NSColor(rgb: 0xFFFFFF)), Color(nsColor: NSColor(rgb: 0xE9E6DF))],
          startPoint: .topLeading, endPoint: .bottomTrailing)
      case .dark:
        LinearGradient(
          colors: [Color(nsColor: NSColor(rgb: 0x2A2E35)), Color(nsColor: NSColor(rgb: 0x0E1013))],
          startPoint: .top, endPoint: .bottom)
      case .busy:
        ZStack {
          LinearGradient(
            colors: [Color(nsColor: NSColor(rgb: 0xF2B544)), Color(nsColor: NSColor(rgb: 0xC2421F))],
            startPoint: .topLeading, endPoint: .bottomTrailing)
          RadialGradient(
            colors: [Color(nsColor: NSColor(rgb: 0xFFF1C4)).opacity(0.9), .clear], center: UnitPoint(x: 0.7, y: 0.3),
            startRadius: 0, endRadius: 60)
          RadialGradient(
            colors: [Color(nsColor: NSColor(rgb: 0x3B1206)).opacity(0.8), .clear], center: UnitPoint(x: 0.15, y: 0.9),
            startRadius: 0, endRadius: 70)
        }
      }
    }
  }
}
