import SwiftUI

/// A button a place puts in the window's top-left corner, after the sidebar's button and the back button, so
/// every button up there is drawn alike and none lands on another.
struct WindowCornerItem: Identifiable {
  let symbol: String
  let label: LocalizedStringResource
  var shortcut: KeyboardShortcut?
  let action: @MainActor () -> Void

  var id: String { symbol }
}

/// The corner buttons of the place on screen, in order.
struct WindowCornerItems: PreferenceKey {
  static let defaultValue: [WindowCornerItem] = []

  static func reduce(value: inout [WindowCornerItem], nextValue: () -> [WindowCornerItem]) {
    value += nextValue()
  }
}

extension View {
  /// Puts `buttons` in the window's top-left corner while this view is on screen.
  func windowCorner(_ buttons: [WindowCornerItem]) -> some View {
    preference(key: WindowCornerItems.self, value: buttons)
  }
}

/// A button in the window's top-left corner, the size of the sidebar's own.
struct WindowCornerButton: View {
  let button: WindowCornerItem
  @State private var hovering = false

  var body: some View {
    Button(action: button.action) {
      Image(systemName: button.symbol)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(hovering ? Palette.ink : Palette.inkMuted)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering ? Palette.fillStrong : .clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .keyboardShortcut(button.shortcut)
    .onHover { hovering = $0 }
    .help(Text(button.label))
    .accessibilityLabel(Text(button.label))
  }
}
