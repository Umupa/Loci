import SwiftUI

/// The browser's tabs side by side, each its page's title, the one in front raised.
struct TabStrip: View {
  let session: BrowserSession

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      ForEach(session.tabs) { tab in
        TabChip(
          tab: tab, front: tab === session.current, select: { session.select(tab) }, close: { session.close(tab) })
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: Size.tabHeight)
    .padding(.horizontal, 14)
    .padding(.top, Spacing.s)
  }
}

private struct TabChip: View {
  let tab: BrowserTab
  let front: Bool
  let select: () -> Void
  let close: () -> Void
  @State private var hovering = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
    HStack(spacing: Spacing.xxs) {
      Group {
        if let name = tab.name { Text(verbatim: name) } else { Text(.loci("browser.newTab")) }
      }
      .font(.system(size: 12))
      .foregroundStyle(front ? Palette.ink : Palette.inkMuted)
      .lineLimit(1)
      .truncationMode(.tail)
      .frame(maxWidth: .infinity, alignment: .leading)
      Button(action: close) {
        Image(systemName: Symbols.cancel)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Palette.inkMuted)
          .frame(width: 16, height: 16)
          .contentShape(Rectangle())
      }
      .buttonStyle(PressStyle())
      .opacity(front || hovering ? 1 : 0)
      .help(Text(.loci("browser.closeTab")))
      .accessibilityLabel(Text(.loci("browser.closeTab")))
    }
    .padding(.leading, 10)
    .padding(.trailing, Spacing.xxs)
    .frame(maxWidth: 220, maxHeight: .infinity)
    .background(shape.fill(front ? Palette.surface : hovering ? Palette.fillStrong : .clear))
    .overlay(shape.strokeBorder(front ? Palette.lineStrong : .clear, lineWidth: Size.hairline))
    .contentShape(shape)
    .onTapGesture(perform: select)
    .onHover { hovering = $0 }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(front ? [.isButton, .isSelected] : .isButton)
  }
}
