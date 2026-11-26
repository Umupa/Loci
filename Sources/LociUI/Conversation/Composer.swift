import LociModel
import SwiftUI

/// The glass capsule floating at the foot of a conversation: the passage being asked about, the field, a
/// plus menu for adding a file and choosing what Loci runs on, and send or stop.
struct Composer: View {
  /// The main conversation, or the one beside something read, which asks rather than talks and has no
  /// room for adding files.
  enum Style {
    case talk, companion
  }

  let busy: Bool
  @Binding var draft: PassageDraft?
  let send: (String, Passage?) async throws(HostError) -> Done
  let stop: () async -> Void
  /// What `/new` does: start the conversation over. Without it, `/new` is sent like any message.
  var startOver: (() async throws(HostError) -> Done)?
  var style = Style.talk
  /// What adding a file from the plus menu does; without it the menu has no such item.
  var attach: (() -> Void)?
  /// Changes each time the field should take the keyboard; the main conversation's field takes it when it
  /// first shows.
  var focusRequest = 0
  /// Whether the person has typed anything, for what the conversation offers to send instead.
  /// Whether the composer asks for a new panel: what is sent then asks Loci to make one, and `made` hears what
  /// was typed once it has been sent.
  var making: Binding<Bool> = .constant(false)
  var made: (String) -> Void = { _ in }
  /// Words put in from outside, such as asking Loci to change a panel.
  var fill: ComposerFill?
  @Environment(\.locale) private var locale
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var example = 0
  @State private var text = ""
  @State private var selection: TextSelection?
  @State private var stopping = false
  @FocusState private var focused: Bool

  var body: some View {
    HStack(alignment: .bottom, spacing: Spacing.xs) {
      if making.wrappedValue {
        NewPanelCancel { making.wrappedValue = false }
          .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.6)))
      }
      capsule
        .overlay(alignment: .top) {
          if making.wrappedValue {
            Text(.loci("panels.new")).font(.system(size: 13)).foregroundStyle(Palette.ink.opacity(0.5))
              .fixedSize()
              .offset(y: -(Spacing.s + 16))
              .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
          }
        }
    }
    .animation(reduceMotion ? nil : Motion.standard, value: making.wrappedValue)
    .onChange(of: fill) {
      guard let fill else { return }
      text = fill.text
      selection = TextSelection(insertionPoint: text.endIndex)
      focused = true
    }
    .onChange(of: making.wrappedValue) { if making.wrappedValue { focused = true } }
    .task(id: making.wrappedValue) {
      example = 0
      guard making.wrappedValue, !reduceMotion else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: PanelExample.stay)
        if Task.isCancelled { return }
        withAnimation(Motion.swap) { example += 1 }
      }
    }
  }

  private var capsule: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.composer, style: .circular)
    let inset = (Size.composerHeight - Size.composerButton) / 2
    return VStack(alignment: .leading, spacing: 0) {
      if let draft { quoted(draft).padding(.top, 14).padding(.trailing, inset) }
      HStack(alignment: .bottom, spacing: 0) {
        if making.wrappedValue, text.isEmpty {
          SiteBadges(PanelExample.at(example).sources, ring: .clear)
            .padding(.trailing, 10)
            .padding(.bottom, (Size.composerHeight - Size.siteMark) / 2)
        }
        field.padding(.vertical, (Size.composerHeight - Self.lineHeight) / 2)
        Group {
          RuntimeMenu(choosesAgent: style == .talk, attach: attach)
          sendOrStop
        }
        .padding(.bottom, inset)
      }
    }
    .padding(.leading, 18)
    .padding(.trailing, inset)
    .frame(minHeight: Size.composerHeight)
    .background {
      shape.fill(.ultraThinMaterial)
      shape.fill(Palette.composerGlass)
    }
    .overlay(shape.strokeBorder(Palette.composerEdge, lineWidth: Size.hairline))
    .shadow(color: .black.opacity(0.18), radius: 15, y: 8)
    .onChange(of: draft) { if draft != nil { focused = true } }
    .onChange(of: focusRequest) { focused = true }
    .onAppear { if style == .talk { focused = true } }
  }

  private func quoted(_ draft: PassageDraft) -> some View {
    HStack(alignment: .top, spacing: Spacing.xs) {
      QuotedLine(text: draft.excerpt, pictures: !draft.pictures.isEmpty).lineLimit(3)
      Button {
        self.draft = nil
      } label: {
        Image(systemName: Symbols.cancel)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Palette.inkMuted)
          .frame(width: 20, height: 20)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.loci("conversation.removePassage")))
    }
    .padding(.trailing, 6)
  }

  @Environment(\.companionName) private var name
  @Environment(\.projectName) private var projectName

  private var field: some View {
    TextField(text: $text, selection: $selection, axis: .vertical) {
      if !making.wrappedValue {
        if style == .talk, let projectName {
          let shown = ProjectSeal.shortened(projectName)
          Text(.loci("talk.projectPrompt \(shown)")).lineLimit(1)
        } else if name.isEmpty {
          Text(.loci(style == .talk ? "talk.prompt" : "companion.prompt"))
        } else {
          Text(style == .talk ? .loci("talk.prompt \(name)") : .loci("companion.prompt \(name)"))
        }
      }
    }
    .overlay(alignment: .leading) {
      if making.wrappedValue, text.isEmpty {
        PanelExamples(index: example).allowsHitTesting(false)
      }
    }
    .textFieldStyle(.plain)
    .font(.system(size: 15))
    .lineSpacing(3)
    .frame(minHeight: Self.lineHeight)
    .lineLimit(1...8)
    .focused($focused)
    .onSubmit(submit)
    .onKeyPress(.return, phases: .down) { press in
      switch ComposerKey(press.modifiers) {
      case .newLine:
        (text, selection) = ComposerKey.newLine(in: text, at: selection)
        return .handled
      case .send:
        submit()
        return .handled
      case .field:
        return .ignored
      }
    }
  }

  private static let lineHeight: CGFloat = 20

  @ViewBuilder private var sendOrStop: some View {
    if busy {
      RoundButton(symbol: Symbols.stop, glyphSize: 10, label: .loci("conversation.stop"), action: halt)
        .disabled(stopping)
    } else {
      RoundButton(symbol: Symbols.send, glyphSize: 13, label: .loci("conversation.send"), action: submit)
        .disabled(trimmed.isEmpty)
    }
  }

  private var trimmed: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func submit() {
    guard !busy, !trimmed.isEmpty else { return }
    if let startOver, !making.wrappedValue, ComposerKey.isStartOver(trimmed) {
      text = ""
      Task {
        do throws(HostError) {
          _ = try await startOver()
        } catch {
          if text.isEmpty { text = "/new" }
        }
      }
      return
    }
    let typed = trimmed
    let asked = draft
    let request = making.wrappedValue
    text = ""
    draft = nil
    making.wrappedValue = false
    Task {
      do throws(HostError) {
        _ = try await send(request ? NewPanel.request(typed, locale: locale) : typed, asked?.passage)
        if request { made(typed) }
      } catch {
        if text.isEmpty { text = typed }
        if draft == nil { draft = asked }
        if request { making.wrappedValue = true }
      }
    }
  }

  private func halt() {
    stopping = true
    Task {
      await stop()
      stopping = false
    }
  }
}

/// What Return does in the field with these keys held: Shift makes a new line, Command sends, and
/// without either the field sends on its own once any input method has finished.
enum ComposerKey: Equatable {
  case newLine, send, field

  init(_ modifiers: EventModifiers) {
    if modifiers.contains(.shift) {
      self = .newLine
    } else if modifiers.contains(.command) {
      self = .send
    } else {
      self = .field
    }
  }

  /// The text with a line break in place of what is selected, and the caret after it.
  static func newLine(in text: String, at selection: TextSelection?) -> (String, TextSelection) {
    var range = text.endIndex..<text.endIndex
    if case .selection(let picked) = selection?.indices { range = picked }
    var changed = text
    changed.replaceSubrange(range, with: "\n")
    let caret = changed.index(
      changed.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.lowerBound) + 1)
    return (changed, TextSelection(insertionPoint: caret))
  }

  /// `/new` on its own starts the conversation over.
  static func isStartOver(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "/new"
  }
}

/// The circle that sends, or stops Loci while it works: ink when it can, a faint wash when it cannot.
private struct RoundButton: View {
  let symbol: String
  let glyphSize: CGFloat
  let label: LocalizedStringResource
  let action: () -> Void
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: glyphSize, weight: .bold))
        .foregroundStyle(enabled ? Palette.canvas : Palette.ink.opacity(0.45))
        .frame(width: Size.composerButton, height: Size.composerButton)
        .background(enabled ? Palette.ink : Palette.ink.opacity(0.1), in: .circle)
    }
    .buttonStyle(SendPressStyle())
    .accessibilityLabel(Text(label))
  }
}

/// Sending gives under the finger a little more than other buttons do.
private struct SendPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

extension EnvironmentValues {
  /// The name of the project whose conversation is open; `nil` in the chat.
  @Entry var projectName: String?
}
