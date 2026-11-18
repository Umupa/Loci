import SwiftUI

/// Closes the page on top and goes back to the one under it. It sits in the window's top-left corner, beside
/// the sidebar, the size of the sidebar's own button.
struct PageBack: View {
  let back: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: back) {
      Image(systemName: Symbols.back)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(hovering ? Palette.ink : Palette.inkMuted)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering ? Palette.fillStrong : .clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .keyboardShortcut("[", modifiers: .command)
    .onHover { hovering = $0 }
    .help(Text(.loci("page.back")))
    .accessibilityLabel(Text(.loci("page.back")))
  }
}
