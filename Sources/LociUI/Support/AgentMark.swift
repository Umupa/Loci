import LociModel
import SwiftUI

/// An agent's brand mark on a rounded tile, or bare at normalized optical weight when `plain` is true.
struct AgentMark: View {
  let provider: Provider
  var size: CGFloat = 26
  var plain = false
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let dark = scheme == .dark
    let bare = plain && provider != .omp && provider != .fx
    let artSize = size * (bare ? Self.opticalScale(provider) : 0.9)
    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
      .fill(bare ? .clear : tile)
      .overlay {
        if let art = MarkArt.agent(provider, in: scheme) {
          Image(nsImage: art)
            .renderingMode(provider == .grok ? .template : .original)
            .resizable()
            .scaledToFit()
            .foregroundStyle(dark ? Self.lightInk : Self.darkInk)
            .frame(width: artSize, height: artSize)
        }
      }
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }

  static func opticalScale(_ provider: Provider) -> CGFloat {
    switch provider {
    case .codex: 1.75
    case .antigravity: 1.18
    case .grok: 1.05
    case .bundledPi: 1.15
    case .claudeCode: 0.92
    case .cursor, .hermes, .opencode: 0.9
    case .pi: 0.8
    case .omp, .fx: 0.96
    }
  }

  private var tile: Color {
    if provider == .omp || provider == .fx { return Self.darkTile }
    return (scheme == .dark ? Color.white : .black).opacity(0.07)
  }

  private static let darkTile = Color(nsColor: NSColor(rgb: 0x262626))
  private static let darkInk = Color(nsColor: NSColor(rgb: 0x111111))
  private static let lightInk = Color(nsColor: NSColor(rgb: 0xF6F6F6))
}
