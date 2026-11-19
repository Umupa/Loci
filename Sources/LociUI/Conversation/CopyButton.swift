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
        .font(.system(size: 12, weight: .medium))
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
  @Environment(\.codePointer) private var pointer
  @State private var frame = CGRect.zero

  var body: some View {
    let shown = showsCopyButtons || CodePointer.isOver(frame, pointer?.location)
    StructuredText.DefaultCodeBlockStyle().makeBody(configuration: configuration)
      .overlay(alignment: .topTrailing) {
        CopyButton { configuration.codeBlock.copyToPasteboard() }
          .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Palette.surface))
          .padding(Spacing.xxs)
          .opacity(shown ? 1 : 0)
          .allowsHitTesting(shown)
          .animation(Motion.quick, value: shown)
      }
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .named(CodePointer.space))
      } action: {
        frame = $0
      }
  }
}

/// Where the pointer is over a reply, for its code blocks to show their copy buttons.
///
/// Textual lays a view for selecting text over everything it draws, and that view takes the hover from what
/// is under it, so a code block cannot notice the pointer itself. The pointer is followed from outside the
/// text instead, and each code block compares it with its own frame. Only the code blocks read the
/// location, so moving the pointer does not draw the text again.
@MainActor @Observable final class CodePointer {
  var location: CGPoint?

  nonisolated static let space = "codePointer"

  nonisolated static func isOver(_ frame: CGRect, _ location: CGPoint?) -> Bool {
    location.map { frame.contains($0) } ?? false
  }
}

extension EnvironmentValues {
  @Entry var codePointer: CodePointer?
}

extension View {
  /// Follows the pointer over this Markdown so that its code blocks show their copy buttons under it.
  func followsPointerForCode() -> some View {
    modifier(FollowsPointer())
  }
}

private struct FollowsPointer: ViewModifier {
  @State private var pointer = CodePointer()

  func body(content: Content) -> some View {
    content
      .environment(\.codePointer, pointer)
      .coordinateSpace(.named(CodePointer.space))
      .onContinuousHover(coordinateSpace: .named(CodePointer.space)) { phase in
        switch phase {
        case .active(let location): pointer.location = location
        case .ended: pointer.location = nil
        }
      }
  }
}
