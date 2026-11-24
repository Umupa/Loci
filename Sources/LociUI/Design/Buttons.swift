import SwiftUI

/// The button a screen is for: an amber capsule with dark words. Turned off, it falls back to a gray wash with
/// faint words.
struct AmberButtonStyle: ButtonStyle {
  var large = false
  /// Shares the row's width with the buttons beside it.
  var fills = false

  func makeBody(configuration: Configuration) -> some View {
    CapsuleFace(configuration: configuration, look: .amber, large: large, fills: fills)
  }
}

/// A button beside the one a screen is for, such as Cancel: a gray wash with ink words.
struct QuietButtonStyle: ButtonStyle {
  var large = false
  var fills = false

  func makeBody(configuration: Configuration) -> some View {
    CapsuleFace(configuration: configuration, look: .quiet, large: large, fills: fills)
  }
}

/// A button in ink, for a page that does without amber: solid ink with paper words, or a gray wash that turns
/// to solid ink while the pointer is on it. `failure` writes in red on the wash, for trying again.
struct InkButtonStyle: ButtonStyle {
  enum Look { case solid, wash, failure }

  var look: Look = .wash

  func makeBody(configuration: Configuration) -> some View {
    InkFace(configuration: configuration, look: look)
  }
}

private struct InkFace: View {
  let configuration: ButtonStyleConfiguration
  let look: InkButtonStyle.Look
  @Environment(\.isEnabled) private var enabled
  @State private var hovering = false

  var body: some View {
    configuration.label
      .font(Typography.button.weight(.medium))
      .foregroundStyle(words)
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, 14)
      .frame(minWidth: 64, minHeight: 28)
      .background(Capsule().fill(face))
      .contentShape(Capsule())
      .onHover { hovering = $0 }
      .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
      .animation(Motion.quick, value: configuration.isPressed)
      .animation(Motion.quick, value: hovering)
      .opacity(enabled ? 1 : 0.4)
  }

  private var solid: Bool { enabled && (look == .solid || (look == .wash && hovering)) }

  private var face: Color {
    if solid { return Palette.ink }
    if look == .failure, hovering, enabled { return Palette.failure.opacity(0.16) }
    return Palette.fill
  }

  private var words: Color {
    if solid { return Palette.canvas }
    return look == .failure ? Palette.failure : Palette.ink
  }
}

private struct CapsuleFace: View {
  enum Look { case amber, quiet }

  let configuration: ButtonStyleConfiguration
  let look: Look
  let large: Bool
  let fills: Bool
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    configuration.label
      .font(
        look == .quiet ? Typography.button.weight(.medium) : large ? Typography.buttonLarge : Typography.buttonStrong
      )
      .foregroundStyle(words)
      .lineLimit(1)
      .padding(.horizontal, large ? 18 : 15)
      .frame(maxWidth: fills ? .infinity : nil)
      .frame(height: large ? Size.largeButtonHeight : Size.primaryHeight)
      .background(Capsule().fill(face))
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
      .animation(Motion.quick, value: configuration.isPressed)
      .animation(Motion.quick, value: enabled)
  }

  private var face: Color {
    switch look {
    case .quiet: Palette.fillStrong
    case .amber: enabled ? Palette.accent : Palette.fillStrong
    }
  }

  private var words: Color {
    switch look {
    case .quiet: enabled ? Palette.ink : Palette.inkFaint
    case .amber: enabled ? Palette.onAccent : Palette.inkFaint
    }
  }
}

/// A switch in amber, shown without its label: the knob springs across and the track fills with amber under a
/// dark knob.
struct AmberSwitch: ToggleStyle {
  var small = false

  func makeBody(configuration: Configuration) -> some View {
    let on = configuration.isOn
    Capsule()
      .fill(on ? Palette.accent : Palette.fillStrong)
      .overlay(Capsule().strokeBorder(on ? .clear : Palette.lineStrong, lineWidth: Size.hairline))
      .overlay(alignment: on ? .trailing : .leading) {
        Circle()
          .fill(on ? Palette.onAccent : .white)
          .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
          .padding(2)
      }
      .frame(width: small ? 30 : 36, height: small ? 18 : 21)
      .contentShape(Capsule())
      .onTapGesture { withAnimation(.spring(duration: 0.3, bounce: 0.35)) { configuration.isOn.toggle() } }
      .accessibilityElement()
      .accessibilityAddTraits(.isToggle)
      .accessibilityValue(on ? Text(verbatim: "1") : Text(verbatim: "0"))
      .accessibilityAction { configuration.isOn.toggle() }
  }
}
