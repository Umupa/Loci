import AppKit
import SwiftUI

/// What can be done with a selected passage.
struct PassageActions {
  var highlight: (NSRange) -> Void
  var think: (NSRange, String) -> Void
  /// `nil` where there is no mentor to ask.
  var ask: ((NSRange, String) -> Void)?
}

/// The small bar over a selection: highlight it, write a thought on it, or ask about it.
struct PassageBar: View {
  let actions: PassageActions
  let range: NSRange
  let done: () -> Void
  @State private var writing: Writing?
  @State private var text = ""
  @FocusState private var focused: Bool

  enum Writing {
    case thought, question
  }

  var body: some View {
    Group {
      if let writing {
        TextField(text: $text, axis: .vertical) {
          Text(writing == .thought ? .loci("passage.thoughtPrompt") : .loci("passage.questionPrompt"))
        }
        .textFieldStyle(.plain)
        .lineLimit(1...6)
        .focused($focused)
        .onSubmit(submit)
        .frame(width: Size.termCardWidth)
        .onAppear { focused = true }
      } else {
        HStack(spacing: Spacing.xxs) {
          button(.loci("passage.highlight"), Symbols.highlight) {
            actions.highlight(range)
            done()
          }
          button(.loci("passage.thought"), Symbols.thought) { writing = .thought }
          if actions.ask != nil {
            button(.loci("passage.ask"), Symbols.ask) { writing = .question }
          }
        }
      }
    }
    .padding(Spacing.xs)
  }

  private func button(_ title: LocalizedStringResource, _ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label {
        Text(title)
      } icon: {
        Image(systemName: symbol)
      }
      .labelStyle(.titleAndIcon)
      .padding(.horizontal, Spacing.xs)
    }
    .buttonStyle(.borderless)
  }

  private func submit() {
    let written = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !written.isEmpty else { return }
    switch writing {
    case .thought: actions.think(range, written)
    case .question: actions.ask?(range, written)
    case nil: return
    }
    done()
  }
}

/// Shows the `PassageBar` under a finished selection.
@MainActor
final class PassagePopover {
  private var popover: NSPopover?

  func show(_ actions: PassageActions, for range: NSRange, at rect: CGRect, in view: NSView) {
    close()
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = false
    let controller = NSHostingController(
      rootView: PassageBar(actions: actions, range: range) { [weak self] in self?.close() })
    controller.sizingOptions = .preferredContentSize
    popover.contentViewController = controller
    popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    self.popover = popover
  }

  func close() {
    popover?.close()
    popover = nil
  }
}
