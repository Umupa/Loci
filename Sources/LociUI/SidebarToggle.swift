import SwiftUI

/// Hides the sidebar from its own top corner, and brings it back from beside the window's buttons.
struct SidebarToggle: View {
  let shown: Bool
  let toggle: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: toggle) {
      Image(systemName: Symbols.sidebar)
        .font(.system(size: 14))
        .foregroundStyle(hovering ? Palette.ink : Palette.inkMuted)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering && shown ? Palette.fillStrong : .clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .help(Text(shown ? .loci("sidebar.hide") : .loci("sidebar.show")))
    .accessibilityLabel(Text(shown ? .loci("sidebar.hide") : .loci("sidebar.show")))
  }
}
