import LociModel
import SwiftUI

/// The conversation with a mentor, sending through the host. A passage put in `draft` is asked about with
/// the next message; `revealPassage` shows a quoted passage where it was read.
struct ConversationScreen: View {
  @Environment(\.host) private var host
  let mentor: Mentor
  let conversation: Conversation?
  @Binding var draft: PassageDraft?
  let revealPassage: @MainActor (Locator) -> Void

  init(
    mentor: Mentor, conversation: Conversation?, draft: Binding<PassageDraft?>,
    revealPassage: @escaping @MainActor (Locator) -> Void
  ) {
    self.mentor = mentor
    self.conversation = conversation
    _draft = draft
    self.revealPassage = revealPassage
  }

  var body: some View {
    ConversationView(
      mentor: mentor, conversation: conversation, draft: $draft, revealPassage: revealPassage,
      send: { (text: String, passage: Passage?) async throws(HostError) -> Done in
        try await host.run(SendMessage(mentor: mentor.id, text: text, passage: passage))
      },
      stop: { _ = try? await host.run(StopTurn(mentor: mentor.id)) })
  }
}

/// Everything said with one mentor, newest at the bottom, with the input field floating over its foot.
///
/// Each entry is its own view keyed by its first message, so a reply that grows while it streams redraws
/// only itself.
struct ConversationView: View {
  let mentor: Mentor
  let conversation: Conversation?
  @Binding var draft: PassageDraft?
  let revealPassage: @MainActor (Locator) -> Void
  let send: (String, Passage?) async throws(HostError) -> Done
  let stop: () async -> Void

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 14) {
        ForEach(entries) { entry in
          row(entry).transition(.opacity.combined(with: .offset(y: 10)))
        }
        if waiting { StepsCard.waiting.transition(.opacity.combined(with: .offset(y: 10))) }
      }
      .animation(Motion.rise, value: entries.count)
      .padding(.horizontal, 18)
      .padding(.top, 6)
      .padding(.bottom, Spacing.m)
    }
    .defaultScrollAnchor(.bottom)
    .scrollIndicators(.never)
    .mask(
      LinearGradient(
        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03)], startPoint: .top,
        endPoint: .bottom)
    )
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Composer(
        mentor: mentor, context: conversation?.context, busy: conversation?.turn != nil, draft: $draft, send: send,
        stop: stop
      )
      .padding(.horizontal, Spacing.s)
      .padding(.bottom, Spacing.s)
      .padding(.top, Spacing.m)
      .background(
        LinearGradient(
          stops: [.init(color: Palette.well.opacity(0), location: 0), .init(color: Palette.well, location: 0.45)],
          startPoint: .top, endPoint: .bottom))
    }
    .background(Palette.well)
  }

  private var entries: [ConversationEntry] {
    ConversationEntry.layout(
      (conversation?.messages ?? []) + (conversation?.turn?.messages ?? []), live: conversation?.turn != nil)
  }

  /// The mentor is at work but has shown nothing of it yet.
  private var waiting: Bool {
    guard let turn = conversation?.turn else { return false }
    if case .prompt = turn.messages.last?.body { return true }
    return false
  }

  @ViewBuilder private func row(_ entry: ConversationEntry) -> some View {
    switch entry {
    case .asked(_, let prompt):
      AskedMessage(prompt: prompt, revealPassage: revealPassage)
    case .aside(let message):
      AsideLine(message: message)
    case .steps(let steps):
      StepsCard(steps: steps)
    case .reply(_, let text, let streaming):
      ReplyText(text: text, streaming: streaming).padding(.horizontal, 2)
    case .saved:
      SavedChip()
    }
  }
}
