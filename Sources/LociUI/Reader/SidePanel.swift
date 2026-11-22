import SwiftUI

/// Loci's panel at the trailing side of something to read: beside it while the text keeps room to be read, and
/// otherwise laid over it from the edge. Folded away, a button in the top corner brings it back.
struct SidePanel<Main: View, Panel: View>: View {
  let open: Bool
  let beside: Bool
  let width: CGFloat
  let expand: () -> Void
  @ViewBuilder let main: () -> Main
  @ViewBuilder let panel: () -> Panel

  var body: some View {
    HStack(spacing: 0) {
      main()
      if open, beside {
        panel().frame(width: width).transition(.move(edge: .trailing))
      }
    }
    .overlay(alignment: .trailing) {
      if open, !beside {
        panel()
          .frame(width: width)
          .background(Palette.canvas)
          .overlay(alignment: .leading) { Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline) }
          .shadow(color: Palette.warmShadow.opacity(0.22), radius: 24, x: -10)
          .transition(.move(edge: .trailing))
      }
    }
    .overlay(alignment: .topTrailing) {
      if !open {
        PanelButton(title: .loci("panel.expand"), action: expand)
          .glassEffect(.regular, in: .capsule)
          .padding(Spacing.s)
      }
    }
  }
}
