import SwiftUI

/// Frosted glass for something that floats over the page, such as the task dock: a warm wash with the system
/// glass, a hairline edge with light along its top, and a deep soft shadow drawn as a `SoftShadow`. System glass
/// does not render off screen, so a snapshot draws the wash alone, solid.
private struct GlassPanel<S: InsettableShape>: ViewModifier {
  @Environment(\.standIns) private var standIns
  let shape: S

  func body(content: Content) -> some View {
    Group {
      if standIns != nil {
        content.background(shape.fill(Palette.menuFace))
      } else {
        content.background(shape.fill(Palette.floating.opacity(0.5))).glassEffect(.regular, in: shape)
      }
    }
    .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    .overlay(
      shape.strokeBorder(
        LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0)], startPoint: .top, endPoint: .center),
        lineWidth: 1)
    )
    .background { SoftShadow(shape: shape, opacity: 0.18, radius: 26, y: 16) }
  }
}

extension View {
  func glassPanel<S: InsettableShape>(in shape: S) -> some View {
    modifier(GlassPanel(shape: shape))
  }
}
