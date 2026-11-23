import Foundation
import LociModel
import SwiftUI

/// One step of the import panel: its dot on the line, its name with controls at the end, and what it holds,
/// which folds away while the step is off.
struct ImportStep<Trailing: View, Content: View>: View {
  let symbol: String
  let title: LocalizedStringResource
  let on: Bool
  @ViewBuilder let trailing: () -> Trailing
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.s) {
      StepDot(symbol: symbol, on: on)
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(on ? Palette.ink : Palette.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
          trailing()
        }
        .frame(minHeight: 32)
        if on {
          content()
            .padding(.top, Spacing.xs)
            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        }
      }
    }
    .padding(.vertical, 6)
  }
}

/// A step's mark on the line: amber while the step is on.
private struct StepDot: View {
  let symbol: String
  let on: Bool

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(on ? Palette.accent : Palette.inkFaint)
      .frame(width: 32, height: 32)
      .background(Circle().fill(on ? Palette.tint : Palette.menuFace))
      .background(Circle().fill(Palette.menuFace))
      .overlay(Circle().strokeBorder(on ? Palette.accentLine : Palette.lineStrong, lineWidth: 1.5))
      .animation(Motion.quick, value: on)
  }
}

/// The switch at the end of a step.
struct StepSwitch: View {
  @Binding var on: Bool

  var body: some View {
    Toggle(isOn: $on) { EmptyView() }
      .labelsHidden()
      .toggleStyle(AmberSwitch())
  }
}

/// A step's settings in a quiet well, a row each.
struct SettingsWell<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content()) { rows in
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
          if index > 0 { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
          row
        }
      }
    }
    .padding(.horizontal, Spacing.s)
    .padding(.vertical, Spacing.xxs)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.fill))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: Size.hairline)
    }
  }
}

/// A named setting in a `SettingsWell`.
struct SettingRow<Control: View>: View {
  let label: LocalizedStringResource
  @ViewBuilder let control: () -> Control

  var body: some View {
    HStack(spacing: 10) {
      Text(label).font(.system(size: 12.5)).foregroundStyle(Palette.inkMuted).frame(width: 72, alignment: .leading)
      control()
      Spacer(minLength: 0)
    }
    .frame(minHeight: 38)
  }
}

/// One of two ways to keep it, as a card.
struct ChoiceCard<Label: View>: View {
  let chosen: Bool
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
        .labelStyle(CardLabelStyle(chosen: chosen))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.s)
        .frame(height: 40)
        .cardFace(chosen: chosen)
    }
    .buttonStyle(PressStyle())
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }
}

private struct CardLabelStyle: LabelStyle {
  let chosen: Bool

  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 10) {
      configuration.icon.font(.system(size: 15)).foregroundStyle(chosen ? Palette.accent : Palette.inkMuted)
      configuration.title.font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink)
    }
  }
}

/// A quality to download at, with its size.
struct QualityCard: View {
  let name: Text
  let size: Int64?
  let chosen: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 2) {
        name.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
        Text(verbatim: size.map(SpeechModel.bytes) ?? "—")
          .font(Typography.clock)
          .foregroundStyle(chosen ? Palette.accentInk : Palette.inkMuted)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Spacing.s)
      .padding(.vertical, Spacing.xs)
      .cardFace(chosen: chosen)
    }
    .buttonStyle(PressStyle())
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }
}

extension View {
  /// A choice card's face: a quiet well, amber when chosen.
  fileprivate func cardFace(chosen: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    return background(shape.fill(chosen ? Palette.tint : Palette.fill))
      .overlay(shape.strokeBorder(chosen ? Palette.accent : Palette.line, lineWidth: chosen ? 1.5 : 1))
      .contentShape(shape)
      .animation(Motion.quick, value: chosen)
  }
}

/// Languages as the import panel offers them, each named in itself.
enum Languages {
  /// What recognition can be told is spoken.
  static let spoken = ["en", "zh", "ja", "ko", "fr", "de", "es"]
  static let targets = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es"]

  /// The targets, with `current` among them when it is another.
  static func targets(keeping current: String) -> [String] {
    targets.contains(current) ? targets : [current] + targets
  }

  /// `English`, `简体中文`; a tag no locale knows is shown as it is.
  static func name(of tag: String) -> String {
    let named = Locale(identifier: tag).localizedString(forIdentifier: tag) ?? tag
    return named.prefix(1).uppercased() + named.dropFirst()
  }
}
