import SwiftUI

/// The round button at the top right of the main conversation that folds the panel column away and brings it
/// back: solid ink while the column shows, glass while it is folded.
struct PanelColumnToggle: View {
  let shown: Bool
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      Image(systemName: Symbols.home)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(shown ? Palette.canvas : Palette.ink)
        .frame(width: Size.panelToggle, height: Size.panelToggle)
        .background {
          if shown {
            Circle().fill(Palette.ink)
          } else {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Palette.composerGlass)
            Circle().strokeBorder(Palette.composerEdge, lineWidth: Size.hairline)
          }
        }
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .accessibilityLabel(Text(.loci(shown ? "panels.hideColumn" : "panels.showColumn")))
  }
}
