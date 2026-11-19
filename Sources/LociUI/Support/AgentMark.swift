import LociModel
import SwiftUI

/// The agent's mark as supplied for this appearance, on a neutral tile.
struct AgentMark: View {
  let provider: Provider
  var size: CGFloat = 26
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let dark = scheme == .dark
    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
      .fill(tile)
      .overlay {
        if let art = MarkArt.agent(provider, in: scheme) {
          Image(nsImage: art)
            .renderingMode(provider == .grok ? .template : .original)
            .resizable()
            .scaledToFit()
            .foregroundStyle(dark ? Self.lightInk : Self.darkInk)
            .frame(width: size * 0.9, height: size * 0.9)
        }
      }
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }

  private var tile: Color {
    if provider == .omp || provider == .fx { return Self.darkTile }
    return (scheme == .dark ? Color.white : .black).opacity(0.07)
  }

  private static let darkTile = Color(nsColor: NSColor(rgb: 0x262626))
  private static let darkInk = Color(nsColor: NSColor(rgb: 0x111111))
  private static let lightInk = Color(nsColor: NSColor(rgb: 0xF6F6F6))
}
