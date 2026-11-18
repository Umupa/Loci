import AppKit
import SwiftUI
import Textual

/// A small button that copies, and shows a tick for a moment after.
struct CopyButton: View {
  let copy: () -> Void
  @State private var copied = false

  var body: some View {
    Button {
      copy()
      withAnimation(Motion.quick) { copied = true }
      Task {
        try? await Task.sleep(for: .seconds(1.5))
        withAnimation(Motion.quick) { copied = false }
      }
    } label: {
      Image(systemName: copied ? Symbols.done : Symbols.copy)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(copied ? Palette.accentInk : Palette.inkMuted)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(Text(copied ? .loci("conversation.copied") : .loci("conversation.copy")))
  }

  /// Puts plain text on the pasteboard.
  static func put(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}

extension EnvironmentValues {
  /// Copy buttons that wait for the pointer show without it.
  @Entry var showsCopyButtons = false
}

/// A code block in a reply, with a copy button in its top corner while the pointer is over it.
struct CopyableCodeBlock: StructuredText.CodeBlockStyle {
  func makeBody(configuration: Configuration) -> some View {
    CodeBlockView(configuration: configuration)
  }
}

private struct CodeBlockView: View {
  let configuration: StructuredText.CodeBlockStyleConfiguration
  @Environment(\.showsCopyButtons) private var showsCopyButtons
  @State private var hovering = false

  var body: some View {
    StructuredText.DefaultCodeBlockStyle().makeBody(configuration: configuration)
      .overlay(alignment: .topTrailing) {
        CopyButton { configuration.codeBlock.copyToPasteboard() }
          .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Palette.surface))
          .padding(Spacing.xxs)
          .opacity(hovering || showsCopyButtons ? 1 : 0)
      }
      .onHover { hovering = $0 }
  }
}
