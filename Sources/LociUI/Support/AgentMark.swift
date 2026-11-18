import LociModel
import SwiftUI

/// Each agent's own logo on a light tile, or a dark one in the dark, the same wherever an agent is named.
struct AgentMark: View {
  let provider: Provider
  var size: CGFloat = 26
  /// Greyed out, for an agent that is not installed.
  var faded = false
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let dark = scheme == .dark
    let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
    shape
      .fill(LinearGradient(colors: dark ? Self.darkTile : Self.lightTile, startPoint: .top, endPoint: .bottom))
      .overlay(shape.strokeBorder((dark ? Color.white : .black).opacity(0.1), lineWidth: Size.hairline))
      .overlay {
        if let art = MarkArt.agent(provider) {
          Image(nsImage: art)
            .renderingMode(Self.inColor.contains(provider) ? .original : .template)
            .resizable()
            .foregroundStyle(dark ? Self.lightInk : Self.darkInk)
            .frame(width: size * 0.82, height: size * 0.82)
        }
      }
      .frame(width: size, height: size)
      .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
      .grayscale(faded ? 1 : 0)
      .opacity(faded ? 0.45 : 1)
      .accessibilityHidden(true)
  }

  /// The logos drawn in their makers' colours; the rest take the ink of the tile they sit on.
  private static let inColor: Set<Provider> = [.claudeCode, .antigravity]
  private static let lightTile = [Color(nsColor: NSColor(rgb: 0xFFFFFF)), Color(nsColor: NSColor(rgb: 0xF2EFEA))]
  private static let darkTile = [Color(nsColor: NSColor(rgb: 0x3A3735)), Color(nsColor: NSColor(rgb: 0x2A2826))]
  private static let darkInk = Color(nsColor: NSColor(rgb: 0x1F1D1B))
  private static let lightInk = Color(nsColor: NSColor(rgb: 0xF4F1EC))
}
