import LociModel
import SwiftUI

/// The conversation with a mentor, sending through the host.
struct ConversationScreen: View {
  @Environment(\.host) private var host
  let mentor: Mentor
  let conversation: Conversation?

  var body: some View {
    ConversationView(
      mentor: mentor, conversation: conversation,
      send: { (text: String) async throws(HostError) -> Done in
        try await host.run(SendMessage(mentor: mentor.id, text: text))
      },
      stop: { _ = try? await host.run(StopTurn(mentor: mentor.id)) },
      answer: { ask, answer in
        _ = try? await host.run(AnswerPermission(mentor: mentor.id, request: ask.id, answer: answer))
      })
  }
}

/// Everything said with one mentor, newest at the bottom, with a field to say more.
///
/// Each message is its own row keyed by its id, so a reply that grows while it streams redraws only itself.
struct ConversationView: View {
  let mentor: Mentor
  let conversation: Conversation?
  let send: (String) async throws(HostError) -> Done
  let stop: () async -> Void
  let answer: (PermissionAsk, PermissionAsk.Answer) async -> Void

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Spacing.m) {
          ForEach(messages) { message in
            MessageRow(mentor: mentor, message: message, answer: answer)
          }
          if let turn = conversation?.turn, Self.showsWorking(turn) {
            ProgressView().controlSize(.small).padding(.leading, Spacing.xxs)
          }
        }
        .frame(maxWidth: Typography.readingWidth, alignment: .leading)
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.l)
        .frame(maxWidth: .infinity)
      }
      .defaultScrollAnchor(.bottom)
      Composer(busy: conversation?.turn != nil, send: send, stop: stop)
        .frame(maxWidth: Typography.readingWidth)
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.l)
    }
    .background(Palette.canvas)
  }

  private var messages: [Message] {
    (conversation?.messages ?? []) + (conversation?.turn?.messages ?? [])
  }

  /// Whether to show that the mentor is working. A reply arriving shows progress by itself, and a
  /// permission card waiting on the person means the mentor is not working.
  static func showsWorking(_ turn: LiveTurn) -> Bool {
    guard turn.waiting.isEmpty else { return false }
    if case .reply = turn.messages.last?.body { return false }
    return true
  }
}

/// The field at the bottom of a conversation. While the mentor works it offers to stop instead of send.
struct Composer: View {
  let busy: Bool
  let send: (String) async throws(HostError) -> Done
  let stop: () async -> Void
  @State private var text = ""
  @State private var stopping = false
  @FocusState private var focused: Bool

  var body: some View {
    HStack(alignment: .bottom, spacing: Spacing.xs) {
      TextField(text: $text, axis: .vertical) {
        Text(.loci("conversation.prompt"))
      }
      .textFieldStyle(.plain)
      .font(Typography.prompt)
      .lineLimit(1...8)
      .focused($focused)
      .onSubmit(submit)
      .padding(.vertical, Spacing.xs)
      if busy {
        roundButton(Symbols.stop, label: .loci("conversation.stop"), action: halt)
          .disabled(stopping)
      } else {
        roundButton(Symbols.send, label: .loci("conversation.send"), action: submit)
          .disabled(trimmed.isEmpty)
      }
    }
    .padding(.leading, Spacing.m)
    .padding(.trailing, Spacing.xs)
    .padding(.vertical, Spacing.xxs)
    .background(Capsule().fill(Palette.surface))
    .overlay(Capsule().strokeBorder(Palette.line, lineWidth: Size.hairline))
    .onAppear { focused = true }
  }

  private var trimmed: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func roundButton(_ symbol: String, label: LocalizedStringResource, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: Size.sendButton, height: Size.sendButton)
        .foregroundStyle(Palette.onAccent)
        .background(Circle().fill(Palette.accent))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(label))
    .padding(.bottom, Spacing.xxs)
  }

  private func submit() {
    guard !busy, !trimmed.isEmpty else { return }
    let sent = trimmed
    text = ""
    Task {
      do throws(HostError) {
        _ = try await send(sent)
      } catch {
        if text.isEmpty { text = sent }
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
