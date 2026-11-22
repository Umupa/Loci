import SwiftUI

/// The field at the top of the courses page: what to learn. Return or the send button hands over what was typed;
/// the button fills with amber once there is something to send.
struct WishField: View {
  @Binding var text: String
  let send: (String) -> Void
  @FocusState private var focused: Bool

  var body: some View {
    let ready = !wish.isEmpty
    HStack(spacing: Spacing.s) {
      WishStar()
        .foregroundStyle(Palette.accent)
        .frame(width: 18, height: 18)
      TextField(text: $text, prompt: Text(.loci("course.wish")).foregroundStyle(Palette.inkFaint)) {
        Text(.loci("course.wish"))
      }
      .textFieldStyle(.plain)
      .font(.system(size: 16))
      .foregroundStyle(Palette.ink)
      .focused($focused)
      .onSubmit(submit)
      Button(action: submit) {
        Image(systemName: Symbols.send)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(ready ? Palette.onAccent : Palette.inkMuted)
          .frame(width: 36, height: 36)
          .background(Circle().fill(ready ? Palette.accent : Palette.fillStrong))
          .scaleEffect(ready ? 1 : 0.94)
          .animation(.spring(duration: 0.3, bounce: 0.45), value: ready)
      }
      .buttonStyle(.plain)
      .disabled(!ready)
      .accessibilityLabel(Text(.loci("course.start")))
    }
    .padding(.leading, 20)
    .padding(.trailing, Spacing.xs)
    .frame(height: Size.wishField)
    .background(Capsule().fill(Palette.composerGlass))
    .anchorPreference(key: GrowthOrigins.self, value: .bounds) { [.wish: $0] }
    .glassEffect(.regular, in: .capsule)
    .overlay { Capsule().strokeBorder(Palette.composerEdge, lineWidth: Size.hairline) }
    .shadow(color: Palette.warmShadow.opacity(0.1), radius: 12, y: 6)
    .contentShape(Capsule())
    .onTapGesture { focused = true }
  }

  private var wish: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  private func submit() {
    guard !wish.isEmpty else { return }
    send(wish)
  }
}

/// Two four-pointed stars, a large and a small: a wish being made.
struct WishStar: View {
  var body: some View {
    Canvas { context, size in
      let unit = min(size.width, size.height) / 18
      context.scaleBy(x: unit, y: unit)
      context.stroke(
        star(center: CGPoint(x: 9, y: 7), reach: 5.5), with: .foreground,
        style: StrokeStyle(lineWidth: 1.5 / unit * 0.9, lineJoin: .round))
      context.stroke(
        star(center: CGPoint(x: 14.5, y: 14.5), reach: 2), with: .foreground,
        style: StrokeStyle(lineWidth: 1.5 / unit * 0.9, lineJoin: .round))
    }
    .accessibilityHidden(true)
  }

  private func star(center: CGPoint, reach: CGFloat) -> Path {
    var path = Path()
    let bend = reach * 0.18
    path.move(to: CGPoint(x: center.x, y: center.y - reach))
    path.addQuadCurve(
      to: CGPoint(x: center.x + reach, y: center.y), control: CGPoint(x: center.x + bend, y: center.y - bend))
    path.addQuadCurve(
      to: CGPoint(x: center.x, y: center.y + reach), control: CGPoint(x: center.x + bend, y: center.y + bend))
    path.addQuadCurve(
      to: CGPoint(x: center.x - reach, y: center.y), control: CGPoint(x: center.x - bend, y: center.y + bend))
    path.addQuadCurve(
      to: CGPoint(x: center.x, y: center.y - reach), control: CGPoint(x: center.x - bend, y: center.y - bend))
    path.closeSubpath()
    return path
  }
}
