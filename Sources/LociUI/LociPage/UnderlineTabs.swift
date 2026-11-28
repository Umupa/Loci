import SwiftUI

/// The tabs of the companion's home page in a row, its own first and its settings after a short rule, with an
/// amber line under the one shown that slides to the next one chosen.
struct UnderlineTabs: View {
  @Binding var selection: LociTab
  @Environment(\.reducesMotion) private var reduceMotion
  @Namespace private var line

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(LociTab.groups.enumerated()), id: \.offset) { index, group in
        if index > 0 {
          Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline, height: 14).padding(.horizontal, 10)
        }
        ForEach(group, id: \.self) { tab in
          button(tab)
        }
      }
    }
    .padding(.horizontal, -Self.inset)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func button(_ tab: LociTab) -> some View {
    let chosen = tab == selection
    return Button {
      withAnimation(reduceMotion ? nil : Motion.slider) { selection = tab }
    } label: {
      Text(tab.title)
        .font(.system(size: 13.5, weight: chosen ? .semibold : .regular))
        .foregroundStyle(chosen ? Palette.ink : Palette.inkMuted)
        .padding(.horizontal, Self.inset)
        .padding(.top, 11)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
          if chosen {
            Capsule()
              .fill(Palette.accent)
              .frame(height: 2.5)
              .padding(.horizontal, Self.inset)
              .matchedGeometryEffect(id: "line", in: line)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }

  /// Room on each side of a tab's name, which its line leaves.
  private static let inset: CGFloat = 12
}
