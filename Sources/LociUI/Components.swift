import LociModel
import SwiftUI

/// A small outlined label, such as an item's kind on its card.
struct Tag: View {
  let text: Text

  var body: some View {
    text
      .font(Typography.caption)
      .foregroundStyle(Palette.inkMuted)
      .padding(.horizontal, Spacing.xxs)
      .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Palette.line, lineWidth: Size.hairline))
  }
}

/// A large, quiet symbol for a place that has nothing in it yet.
struct EmptyMark: View {
  let symbol: String

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: Size.emptySymbol, weight: .light))
      .foregroundStyle(Palette.inkMuted)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Palette.canvas)
      .accessibilityHidden(true)
  }
}

/// A small capsule segmented control: a thumb the color of a card slides under the chosen segment. The system's control
/// fills the chosen segment with the tint, which would make it a solid amber block.
struct CapsulePicker<Value: Hashable>: View {
  @Binding var selection: Value
  let options: [(value: Value, title: LocalizedStringResource)]
  /// Smaller words and segments, for the head of a narrow panel.
  var compact = false
  @Namespace private var thumb

  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.value) { option in
        let chosen = option.value == selection
        Button {
          withAnimation(Motion.quick) { selection = option.value }
        } label: {
          Text(option.title)
            .font(.system(size: compact ? 12 : 13, weight: chosen ? .medium : .regular))
            .foregroundStyle(chosen ? Palette.ink : Palette.inkMuted)
            .padding(.horizontal, compact ? 10 : 13)
            .padding(.vertical, compact ? 4 : 5)
            .background {
              if chosen {
                Capsule()
                  .fill(Palette.surface)
                  .cardShadow(Capsule())
                  .matchedGeometryEffect(id: "thumb", in: thumb)
              }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
      }
    }
    .padding(2)
    .background(Capsule().fill(Palette.fillStrong))
  }
}

/// A button that shrinks a little while pressed; a small round one, a little more.
struct PressStyle: ButtonStyle {
  var scale = Motion.pressScale

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? scale : 1)
      .animation(Motion.quick, value: configuration.isPressed)
  }
}

/// A pop-up button as System Settings draws one: the chosen title in ink on a light face, sized to that title,
/// with an ink square holding the up and down arrows. The system's own takes the tint for its text and
/// sizes itself to its longest choice.
struct PopupPicker<Value: Hashable>: View {
  @Binding var selection: Value
  let options: [(value: Value, title: Text)]

  var body: some View {
    Menu {
      Picker(selection: $selection) {
        ForEach(options.indices, id: \.self) { index in options[index].title.tag(options[index].value) }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      HStack(spacing: Spacing.xs) {
        (options.first { $0.value == selection }?.title ?? Text(verbatim: ""))
          .font(.system(size: 12.5))
          .foregroundStyle(Palette.ink)
          .lineLimit(1)
        Image(systemName: Symbols.popup)
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(Palette.onAccent)
          .frame(width: Spacing.m, height: Spacing.m)
          .background(RoundedRectangle(cornerRadius: 4).fill(Palette.accent))
      }
      .padding(.leading, 9)
      .padding(.trailing, 3)
      .frame(height: 22)
      .background(RoundedRectangle(cornerRadius: 6).fill(Palette.thumb))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
      .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
  }
}
