import SwiftUI

/// A borderless trigger: what it opens on, with its chevron right after, washed under the pointer or while open.
struct PlainTriggerLabel<Content: View>: View {
  var muted = false
  var open = false
  @ViewBuilder let content: () -> Content
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 6) {
      content()
      Image(systemName: Symbols.unfold)
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(hovering || open ? Palette.ink : Palette.inkFaint)
        .rotationEffect(.degrees(open ? 180 : 0))
    }
    .foregroundStyle(muted && !hovering && !open ? Palette.inkMuted : Palette.ink)
    .padding(.horizontal, 8)
    .frame(height: 30)
    .background(
      RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering || open ? Palette.fillStrong : .clear)
    )
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
  }
}

/// A row of a menu Loci draws itself: washed under the pointer, selected when highlighted or active.
struct MenuRowStyle: ButtonStyle {
  var chosen = false

  func makeBody(configuration: Configuration) -> some View {
    RowBody(configuration: configuration, chosen: chosen)
  }

  private struct RowBody: View {
    let configuration: Configuration
    let chosen: Bool
    @State private var hovering = false

    var body: some View {
      configuration.label
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(chosen ? Palette.selection : hovering || configuration.isPressed ? Palette.fill : .clear)
        )
        .onHover { hovering = $0 }
    }
  }
}

/// A rule between parts of a popover.
struct Hairline: View {
  var body: some View {
    Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline)
  }
}
