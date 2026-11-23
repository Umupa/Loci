import AppKit
import SwiftUI

/// How subtitles look, in the panel beside the player: the style on three kinds of picture, the presets, each
/// language's lettering, how the two languages show, how high they sit, and going back to the standard.
struct SubtitleStylePanel: View {
  @Binding var style: SubtitleStyle
  @Binding var mode: SubtitleMode
  let close: () -> Void
  @State private var editing = Language.translation

  enum Language: Hashable {
    case translation, original
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          SubtitleBoard(style: style, mode: mode)
          section(.loci("caption.presets")) { presets }
          section(.loci("caption.lettering")) { lettering }
          section(.loci("caption.bilingual")) { bilingual }
          section(.loci("caption.position")) {
            StyleCard {
              StyleRow(.loci("caption.lift")) {
                ValueStepper(text: "\(style.lift)%") { style.raise(by: $0) }
              }
            }
          }
          Button {
            withAnimation(Motion.quick) { style = .standard }
          } label: {
            Label {
              Text(.loci("caption.reset"))
            } icon: {
              Image(systemName: Symbols.restart)
            }
          }
          .controlSize(.large)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.l)
      }
      .scrollIndicators(.never)
    }
  }

  private var header: some View {
    HStack(spacing: 7) {
      Image(systemName: Symbols.subtitleStyle).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.accent)
        .environment(\.locale, Locale(identifier: "en"))
      Text(.loci("caption.title")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
      Spacer(minLength: 0)
      RoundIconButton(
        symbol: Symbols.cancel, title: .loci("caption.close"), size: Size.iconButton, symbolSize: 12,
        action: close)
    }
    .padding(.horizontal, 18)
    .frame(height: 60)
  }

  private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.inkMuted)
      content()
    }
  }

  private var presets: some View {
    HStack(spacing: 6) {
      ForEach(SubtitleStyle.Preset.allCases, id: \.self) { preset in
        PresetTile(preset: preset, chosen: style.preset == preset) {
          withAnimation(Motion.quick) { style.choose(preset) }
        }
      }
    }
  }

  private var lettering: some View {
    VStack(spacing: Spacing.xs) {
      Picker(selection: $editing) {
        Text(.loci("caption.translation")).tag(Language.translation)
        Text(.loci("caption.original")).tag(Language.original)
      } label: {
        EmptyView()
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      let lettering = editing == .translation ? $style.translation : $style.original
      StyleCard {
        StyleRow(.loci("caption.font")) {
          Picker(selection: lettering.font) {
            ForEach(SubtitleFont.allCases, id: \.self) { font in Text(font.name).tag(font) }
          } label: {
            EmptyView()
          }
          .labelsHidden()
          .fixedSize()
        }
        StyleRow(.loci("caption.size")) {
          ValueStepper(text: "\(lettering.wrappedValue.size)") { lettering.wrappedValue.resize(by: $0) }
        }
        StyleRow(.loci("caption.color")) {
          HStack(spacing: Spacing.xs) {
            ForEach(SubtitleColor.allCases, id: \.self) { color in
              Swatch(color: color, chosen: lettering.wrappedValue.color == color) {
                lettering.wrappedValue.color = color
              }
            }
          }
        }
        StyleRow(.loci("caption.bold"), last: true) {
          Toggle(isOn: lettering.bold) { EmptyView() }.toggleStyle(AmberSwitch(small: true)).labelsHidden()
        }
      }
    }
  }

  private var bilingual: some View {
    Picker(
      selection: Binding {
        Bilingual(mode: mode, order: style.order)
      } set: { choice in
        withAnimation(Motion.quick) { choice.apply(to: &mode, &style.order) }
      }
    ) {
      ForEach(Bilingual.allCases, id: \.self) { choice in Text(choice.name).tag(choice) }
    } label: {
      EmptyView()
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }
}

/// A preset as a small picture with a subtitle on it, ringed in amber when chosen.
private struct PresetTile: View {
  @Environment(\.locale) private var locale
  let preset: SubtitleStyle.Preset
  let chosen: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      VStack(spacing: 6) {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color(nsColor: NSColor(rgb: 0x4A5560)), Color(nsColor: NSColor(rgb: 0x1E2328))],
              startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .aspectRatio(4 / 3, contentMode: .fit)
          .overlay(alignment: .bottom) {
            SubtitleOverlay(
              lines: [
                SubtitleLine(text: KeyPointWords.string(.loci("caption.word"), in: locale), translated: true)
              ],
              style: SubtitleStyle.standard.choosing(preset), referenceWidth: 150
            )
            .padding(.bottom, 4)
          }
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(chosen ? Palette.accent : Palette.lineStrong, lineWidth: chosen ? 2 : Size.hairline)
          )
          .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(chosen ? Palette.tint : .clear).padding(-3))
        Text(preset.name)
          .font(.system(size: 12, weight: chosen ? .semibold : .regular))
          .foregroundStyle(chosen ? Palette.ink : Palette.inkMuted)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }
}

/// A color to letter subtitles in, ringed in amber when chosen.
private struct Swatch: View {
  let color: SubtitleColor
  let chosen: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      Circle()
        .fill(color.color)
        .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: Size.hairline))
        .frame(width: 20, height: 20)
        .padding(3)
        .overlay(Circle().strokeBorder(chosen ? Palette.accent : .clear, lineWidth: 1.5))
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .help(Text(color.name))
    .accessibilityLabel(Text(color.name))
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }
}

/// A number with arrows to step it up and down, as the system's stepper with its value beside it.
private struct ValueStepper: View {
  let text: String
  let step: (Int) -> Void

  var body: some View {
    HStack(spacing: 6) {
      Text(verbatim: text).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Palette.ink)
      Stepper {
        EmptyView()
      } onIncrement: {
        step(1)
      } onDecrement: {
        step(-1)
      }
      .labelsHidden()
      .controlSize(.small)
    }
  }
}

/// Rows on a quiet card, a hairline between them.
private struct StyleCard<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(spacing: 0) { content() }
      .padding(.horizontal, Spacing.s)
      .padding(.vertical, 3)
      .background(RoundedRectangle(cornerRadius: Radius.group, style: .continuous).fill(Palette.fill))
      .overlay(
        RoundedRectangle(cornerRadius: Radius.group, style: .continuous).strokeBorder(
          Palette.line, lineWidth: Size.hairline))
  }
}

/// A setting's name and its control, a hairline under all but the last.
private struct StyleRow<Control: View>: View {
  let title: LocalizedStringResource
  var last = false
  @ViewBuilder let control: () -> Control

  init(_ title: LocalizedStringResource, last: Bool = false, @ViewBuilder control: @escaping () -> Control) {
    self.title = title
    self.last = last
    self.control = control
  }

  var body: some View {
    HStack {
      Text(title).font(.system(size: 13)).foregroundStyle(Palette.ink)
      Spacer(minLength: Spacing.xs)
      control()
    }
    .frame(minHeight: 34)
    .overlay(alignment: .bottom) {
      if !last { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
    }
  }
}

extension SubtitleStyle {
  /// This style with `preset` chosen.
  func choosing(_ preset: Preset) -> SubtitleStyle {
    var style = self
    style.choose(preset)
    return style
  }
}
