import SwiftUI

/// A settings page in the grammar of System Settings: an icon tile and a title, then grouped lists.
struct SettingsPage<Content: View>: View {
  let symbol: String
  let title: LocalizedStringResource
  /// Wider for a page with a table in it.
  var width = Size.settingsWidth
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(spacing: Spacing.s) {
          Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Palette.inkMuted)
            .frame(width: Size.settingsTile, height: Size.settingsTile)
            .background(Palette.fill, in: .rect(cornerRadius: 10))
            .accessibilityHidden(true)
          Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.ink)
        }
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Spacing.xl)
      .padding(.top, 30)
      .padding(.bottom, 60)
      .frame(maxWidth: width)
      .frame(maxWidth: .infinity)
    }
    .background(Palette.canvas)
  }
}

/// A titled group of rows on a card, with thin lines between them.
struct SettingsGroup<Content: View>: View {
  /// `nil` for a list that needs no name, such as the only one on its page.
  let title: LocalizedStringResource?
  /// Where the line between rows starts: under the text, past a leading mark when rows have one.
  var inset: CGFloat = 12
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let title {
        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink).padding(.leading, 10)
      }
      VStack(spacing: 0) {
        Group(subviews: content) { rows in
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            if index > 0 {
              Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline).padding(.leading, inset)
            }
            row
          }
        }
      }
      .background(RoundedRectangle(cornerRadius: Radius.group, style: .continuous).fill(Palette.surface))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.group, style: .continuous).strokeBorder(
          Palette.line, lineWidth: Size.hairline)
      }
      .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }
  }
}

/// One row of a settings group.
struct SettingsRow<Leading: View, Trailing: View>: View {
  @ViewBuilder let leading: Leading
  @ViewBuilder let trailing: Trailing

  var body: some View {
    HStack(spacing: 10) {
      leading
      Spacer(minLength: Spacing.s)
      trailing
    }
    .font(.system(size: 13))
    .foregroundStyle(Palette.ink)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(minHeight: 44)
  }
}

/// A push button as System Settings draws one in a row: the words on a light face with a hairline around it.
struct PushStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12.5, weight: .medium))
      .foregroundStyle(isEnabled ? Palette.ink : Palette.inkFaint)
      .padding(.horizontal, 11)
      .frame(height: 22)
      .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.thumb))
      .overlay {
        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
      }
      .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
      .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
      .animation(Motion.quick, value: configuration.isPressed)
  }
}
