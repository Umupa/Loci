import LociModel
import SwiftUI

/// A mentor's mark: a circle in the mentor's color with the first character of its name.
struct Avatar: View {
  let mentor: Mentor
  let size: CGFloat

  var body: some View {
    Circle()
      .fill(mentor.color.color)
      .frame(width: size, height: size)
      .overlay {
        Text(verbatim: mentor.name.first.map(String.init) ?? "")
          .font(.system(size: size * Size.avatarGlyphRatio, weight: .semibold))
          .foregroundStyle(Palette.onAccent)
      }
      .accessibilityHidden(true)
  }
}

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
