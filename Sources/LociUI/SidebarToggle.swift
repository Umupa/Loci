import SwiftUI

/// Hides the sidebar from its own top corner, and brings it back from beside the window's buttons.
struct SidebarToggle: View {
  let shown: Bool
  let toggle: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: toggle) {
      SidebarGlyph(shown: shown)
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

/// A window with a pane down its left side and an arrow beside it, pointing in while the sidebar shows and out
/// while it is hidden.
struct SidebarGlyph: View {
  let shown: Bool

  var body: some View {
    ZStack {
      PaneFrame().stroke(style: Self.line)
      Chevron().stroke(style: Self.line)
        .scaleEffect(x: shown ? 1 : -1, anchor: UnitPoint(x: Chevron.center, y: 0.5))
    }
    .frame(width: 17, height: 14)
    .animation(Motion.fold, value: shown)
  }

  private static let line = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
}

/// The window's outline and the edge of the pane inside it.
private struct PaneFrame: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path(roundedRect: rect.insetBy(dx: 0.65, dy: 0.65), cornerRadius: 3.5, style: .continuous)
    let edge = rect.minX + rect.width * 0.36
    path.move(to: CGPoint(x: edge, y: rect.minY + 0.65))
    path.addLine(to: CGPoint(x: edge, y: rect.maxY - 0.65))
    return path
  }
}

/// A small arrow pointing left, in the room right of the pane.
private struct Chevron: Shape {
  /// Where the arrow sits across the glyph, as a fraction of its width.
  static let center = 0.68

  func path(in rect: CGRect) -> Path {
    let middle = CGPoint(x: rect.minX + rect.width * Self.center, y: rect.midY)
    let reach = rect.height * 0.2
    var path = Path()
    path.move(to: CGPoint(x: middle.x + reach / 2, y: middle.y - reach))
    path.addLine(to: CGPoint(x: middle.x - reach / 2, y: middle.y))
    path.addLine(to: CGPoint(x: middle.x + reach / 2, y: middle.y + reach))
    return path
  }
}
