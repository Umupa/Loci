import LociModel
import SwiftUI

/// The card floating at the foot of the conversation: the passage being asked about, the field, and a row
/// with the agent, the model and thinking effort, how full the context is, and send or stop.
struct Composer: View {
  let mentor: Mentor
  let context: ContextUsage?
  let busy: Bool
  @Binding var draft: PassageDraft?
  let send: (String, Passage?) async throws(HostError) -> Done
  let stop: () async -> Void
  /// Only the field and send, for asking alongside an item.
  var plain = false
  @State private var text = ""
  @State private var stopping = false
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let draft { quoted(draft) }
      if plain {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
          field.padding(.bottom, 4)
          sendOrStop
        }
      } else {
        field
      }
      if !plain {
        HStack(spacing: 2) {
          AgentChoiceMenu(mentor: mentor, parts: .agent)
          AgentChoiceMenu(mentor: mentor, parts: .model)
          Spacer(minLength: Spacing.xxs)
          if let context, ContextGauge.fraction(context) != nil { ContextGauge(usage: context) }
          sendOrStop.padding(.leading, Spacing.xxs)
        }
      }
    }
    .padding(.leading, 14)
    .padding(.trailing, 8)
    .padding(.top, 11)
    .padding(.bottom, 8)
    .background(
      RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous).fill(Palette.surface)
        .shadow(color: .black.opacity(0.08), radius: 15, y: 8)
    )
    .overlay {
      RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
        .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
    }
    .background {
      RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
        .stroke(Palette.accent.opacity(focused ? 0.3 : 0), lineWidth: 7)
        .animation(Motion.quick, value: focused)
    }
    .onChange(of: draft) { if draft != nil { focused = true } }
  }

  private func quoted(_ draft: PassageDraft) -> some View {
    HStack(alignment: .top, spacing: Spacing.xs) {
      QuotedLine(text: draft.excerpt).lineLimit(3)
      Button {
        self.draft = nil
      } label: {
        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.inkFaint)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.loci("conversation.removePassage")))
    }
    .padding(.trailing, 6)
  }

  private var field: some View {
    TextField(text: $text, axis: .vertical) {
      Text(.loci("conversation.prompt"))
    }
    .textFieldStyle(.plain)
    .font(.system(size: 14))
    .lineLimit(1...8)
    .focused($focused)
    .onSubmit(submit)
  }

  @ViewBuilder private var sendOrStop: some View {
    if busy {
      RoundButton(symbol: Symbols.stop, label: .loci("conversation.stop"), action: halt).disabled(stopping)
    } else {
      RoundButton(symbol: Symbols.send, label: .loci("conversation.send"), action: submit).disabled(trimmed.isEmpty)
    }
  }

  private var trimmed: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func submit() {
    guard !busy, !trimmed.isEmpty else { return }
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

/// The amber circle that sends, or stops the mentor while it works.
private struct RoundButton: View {
  let symbol: String
  let label: LocalizedStringResource
  let action: () -> Void
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Palette.onAccent)
        .frame(width: Size.sendButton, height: Size.sendButton)
        .background(Circle().fill(Palette.accent.gradient))
        .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: Size.hairline))
        .opacity(enabled ? 1 : 0.45)
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(Text(label))
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
