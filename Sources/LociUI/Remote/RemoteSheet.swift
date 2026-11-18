import SwiftUI

extension View {
  /// Shows these views on a card of the system's glass that drops over the window, with the window dimmed
  /// behind it. Escape closes it; a click on the dimmed window does not, so a pairing is never dropped by
  /// accident. `centered` centers them, as when two Macs compare a code.
  func remoteSheet(centered: Bool = false, close: @escaping () -> Void) -> some View {
    ZStack(alignment: .top) {
      Palette.scrim.contentShape(Rectangle()).ignoresSafeArea()
      VStack(alignment: centered ? .center : .leading, spacing: Spacing.m) { self }
        .multilineTextAlignment(centered ? .center : .leading)
        .padding(.horizontal, 20)
        .padding(.top, centered ? 28 : 22)
        .padding(.bottom, 18)
        .frame(width: Size.remoteSheetWidth)
        .solidGlass(in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 40, y: 30)
        .padding(.top, Size.remoteSheetTop)
        .onExitCommand(perform: close)
    }
  }
}

extension View {
  /// The system's glass under a nearly solid face, as the design draws menus and sheets: what lies behind shows
  /// only as a tint, and the words on top are not blended into it.
  func solidGlass(in shape: some Shape) -> some View {
    background(Palette.menuFace, in: shape)
      .background { Color.clear.glassEffect(.regular, in: shape) }
      .overlay { shape.stroke(Palette.lineStrong, lineWidth: Size.hairline) }
  }
}

/// The bold title of a `RemoteSheet`.
struct SheetTitle: View {
  let text: Text

  var body: some View {
    text.font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.ink).padding(.horizontal, 4)
  }
}

/// The capsule buttons along the foot of a `RemoteSheet`: amber for the answer it asks for, a gray wash
/// for the rest.
struct SheetButtonStyle: ButtonStyle {
  var prominent = false
  /// Shares the row's width with the others.
  var fills = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(Typography.buttonStrong)
      .foregroundStyle(prominent ? Palette.onAccent : Palette.ink)
      .lineLimit(1)
      .padding(.horizontal, Spacing.m)
      .frame(maxWidth: fills ? .infinity : nil)
      .frame(height: Size.primaryHeight)
      .background {
        if prominent {
          Capsule()
            .fill(
              LinearGradient(
                colors: [Palette.accent.mix(with: .white, by: 0.18), Palette.accent], startPoint: .top,
                endPoint: .bottom)
            )
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
        } else {
          Capsule().fill(Palette.fillStrong)
        }
      }
      .overlay(Capsule().strokeBorder(prominent ? .black.opacity(0.12) : Palette.line, lineWidth: Size.hairline))
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
      .animation(Motion.quick, value: configuration.isPressed)
  }
}

/// A thin ring turning while something is being looked for or waited on.
struct Spinner: View {
  @Environment(\.standIns) private var standIns
  @State private var turned = false

  var body: some View {
    Circle()
      .strokeBorder(
        AngularGradient(
          colors: [.clear, Palette.inkMuted], center: .center, startAngle: .degrees(36), endAngle: .degrees(360)),
        lineWidth: 1.6
      )
      .frame(width: 14, height: 14)
      .rotationEffect(.degrees(turned ? 360 : 0))
      .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turned)
      .onAppear { turned = standIns == nil }
      .accessibilityHidden(true)
  }
}
