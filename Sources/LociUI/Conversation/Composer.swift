import LociModel
import SwiftUI

/// The glass card floating at the foot of a conversation: the passage being asked about, the field, and a
/// row with adding a file, what Loci runs on, how full the context is, and send or stop.
struct Composer: View {
  /// The main conversation, or the one beside something read, which asks rather than talks and has no
  /// room for adding files.
  enum Style {
    case talk, companion
  }

  let context: ContextUsage?
  let busy: Bool
  @Binding var draft: PassageDraft?
  let send: (String, Passage?) async throws(HostError) -> Done
  let stop: () async -> Void
  /// What `/new` does: start the conversation over. Without it, `/new` is sent like any message.
  var startOver: (() async throws(HostError) -> Done)?
  var style = Style.talk
  /// What the plus button does; without it there is none.
  var attach: (() -> Void)?
  /// Changes each time the field should take the keyboard; the main conversation's field takes it when it
  /// first shows.
  var focusRequest = 0
  @State private var text = ""
  @State private var selection: TextSelection?
  @State private var stopping = false
  @FocusState private var focused: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.composer, style: .continuous)
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let draft { quoted(draft) }
      field
      HStack(spacing: 6) {
        if let attach {
          AttachButton(action: attach)
        }
        RuntimeMenu(namesAgent: style == .talk)
        Spacer(minLength: Spacing.xxs)
        if let context, ContextGauge.fraction(context) != nil { ContextGauge(usage: context) }
        sendOrStop
      }
    }
    .padding(.leading, Spacing.m)
    .padding([.top, .bottom, .trailing], 10)
    .glassEffect(.regular, in: shape)
    .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    .shadow(color: .black.opacity(0.10), radius: 15, y: 10)
    .onChange(of: draft) { if draft != nil { focused = true } }
    .onChange(of: focusRequest) { focused = true }
    .onAppear { if style == .talk { focused = true } }
  }

  private func quoted(_ draft: PassageDraft) -> some View {
    HStack(alignment: .top, spacing: Spacing.xs) {
      QuotedLine(text: draft.excerpt).lineLimit(3)
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

  private var field: some View {
    TextField(text: $text, selection: $selection, axis: .vertical) {
      Text(.loci(style == .talk ? "talk.prompt" : "companion.prompt"))
    }
    .textFieldStyle(.plain)
    .font(.system(size: 14.5))
    .lineSpacing(3)
    .frame(minHeight: 22)
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

  @ViewBuilder private var sendOrStop: some View {
    if busy {
      RoundButton(symbol: Symbols.stop, glyphSize: 11, label: .loci("conversation.stop"), action: halt)
        .disabled(stopping)
    } else {
      RoundButton(symbol: Symbols.send, glyphSize: 14, label: .loci("conversation.send"), action: submit)
        .disabled(trimmed.isEmpty)
    }
  }

  private var trimmed: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func submit() {
    guard !busy, !trimmed.isEmpty else { return }
    if let startOver, ComposerKey.isStartOver(trimmed) {
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
    let sent = trimmed
    let asked = draft
    text = ""
    draft = nil
    Task {
      do throws(HostError) {
        _ = try await send(sent, asked?.passage)
      } catch {
        if text.isEmpty { text = sent }
        if draft == nil { draft = asked }
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

/// The amber circle that sends, or stops Loci while it works.
private struct RoundButton: View {
  let symbol: String
  let glyphSize: CGFloat
  let label: LocalizedStringResource
  let action: () -> Void
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: glyphSize, weight: .semibold))
        .foregroundStyle(enabled ? Palette.onAccent : Palette.inkMuted)
        .frame(width: Size.sendButton, height: Size.sendButton)
        .background(enabled ? Palette.accent : Palette.fillStrong, in: .circle)
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

/// Adds a file, as dropping one does.
private struct AttachButton: View {
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: Symbols.attach)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Palette.inkMuted)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(Circle().fill(hovering ? Palette.fill : .clear))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityLabel(Text(.loci("talk.add")))
  }
}

/// How full the agent's context window is, as a ring; opened, the numbers.
struct ContextGauge: View {
  let usage: ContextUsage
  @State private var open = false

  var body: some View {
    Button {
      open.toggle()
    } label: {
      ZStack {
        Circle().stroke(Palette.fillStrong, lineWidth: 2.2)
        Circle()
          .trim(from: 0, to: Self.fraction(usage) ?? 0)
          .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .frame(width: 14, height: 14)
      .padding(.horizontal, 5)
      .frame(height: 26)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(.loci("conversation.context")))
    .accessibilityValue(Text(verbatim: Self.label(usage)))
    .popover(isPresented: $open, arrowEdge: .top) {
      VStack(alignment: .leading, spacing: 6) {
        Capsule().fill(Palette.fillStrong).frame(height: 4)
          .overlay(alignment: .leading) {
            GeometryReader { proxy in
              Capsule().fill(Palette.accent).frame(width: proxy.size.width * (Self.fraction(usage) ?? 0))
            }
          }
        Text(verbatim: Self.label(usage)).font(Typography.mono).foregroundStyle(Palette.inkMuted)
      }
      .padding(Spacing.s)
      .frame(width: 180)
    }
  }

  /// Used of the whole, or `nil` when the agent did not say both.
  nonisolated static func fraction(_ usage: ContextUsage) -> Double? {
    guard let used = usage.used, let window = usage.window, window > 0 else { return nil }
    return min(1, Double(used) / Double(window))
  }

  nonisolated static func label(_ usage: ContextUsage) -> String {
    func thousands(_ tokens: Int?) -> String { tokens.map { "\(($0 + 500) / 1000)k" } ?? "?" }
    return "\(thousands(usage.used)) / \(thousands(usage.window))"
  }
}
