import SwiftUI

/// Shows or plays only the key points: an icon alone, the same size as the translate button, amber with a dark
/// icon while on.
struct OnlyKeyPointsButton: View {
  @Binding var on: Bool
  @State private var hovering = false

  var body: some View {
    Button {
      withAnimation(Motion.quick) { on.toggle() }
    } label: {
      FoldOthers()
        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        .frame(width: 15, height: 15)
        .foregroundStyle(on ? Palette.onAccent : hovering ? Palette.ink : Palette.inkMuted)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(
          RoundedRectangle(cornerRadius: Radius.row).fill(on ? Palette.accent : hovering ? Palette.fillStrong : .clear)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .help(Text(.loci("keypoints.only")))
    .accessibilityLabel(Text(.loci("keypoints.only")))
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}

/// The rest folded away: a line above and a line below, with a fold pointing in from each between them.
struct FoldOthers: Shape {
  func path(in rect: CGRect) -> Path {
    let x = { (share: CGFloat) in rect.minX + rect.width * share }
    let y = { (share: CGFloat) in rect.minY + rect.height * share }
    var path = Path()
    path.move(to: CGPoint(x: x(0), y: y(1.0 / 16)))
    path.addLine(to: CGPoint(x: x(1), y: y(1.0 / 16)))
    path.move(to: CGPoint(x: x(0), y: y(15.0 / 16)))
    path.addLine(to: CGPoint(x: x(1), y: y(15.0 / 16)))
    path.move(to: CGPoint(x: x(0.25), y: y(0.25)))
    path.addLine(to: CGPoint(x: x(0.5), y: y(0.375)))
    path.addLine(to: CGPoint(x: x(0.75), y: y(0.25)))
    path.move(to: CGPoint(x: x(0.25), y: y(0.75)))
    path.addLine(to: CGPoint(x: x(0.5), y: y(0.625)))
    path.addLine(to: CGPoint(x: x(0.75), y: y(0.75)))
    return path
  }
}
