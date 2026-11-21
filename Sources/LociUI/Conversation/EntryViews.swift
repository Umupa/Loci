import LociModel
import SwiftUI

/// What the person said, under the passage it asks about; the passage shows where it was read.
struct AskedMessage: View {
  let prompt: Prompt
  let revealPassage: @MainActor (Locator) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let passage = prompt.passage {
        Button {
          revealPassage(passage.locator)
        } label: {
          QuotedLine(text: passage.excerpt)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
      }
      Text(verbatim: prompt.text).textSelection(.enabled)
    }
  }
}

/// Quoted words in serif, behind a thin amber bar.
struct QuotedLine: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      Rectangle().fill(Palette.accent).frame(width: 2)
      Text(serif: text, Typography.quote)
        .foregroundStyle(Palette.inkMuted)
        .lineSpacing(3)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .fixedSize(horizontal: false, vertical: true)
    .contentShape(Rectangle())
  }
}

/// What Loci says when a turn did not finish: one sentence, never the agent's own error output.
struct EndedTurn: View {
  let ending: TurnEnding

  var body: some View {
    switch ending {
    case .interrupted: Text(.loci("ended.interrupted"))
    case .failed: Text(.loci("ended.failed"))
    case .unstarted(let provider, let failure): Self.unstarted(provider, failure)
    }
  }

  /// Why Loci's agent did not start, beginning with the agent's name.
  static func unstarted(_ provider: Provider, _ failure: AgentStartFailure) -> Text {
    let said: LocalizedStringResource =
      switch failure {
      case .notInstalled: .loci("conversation.agentNotInstalled")
      case .wouldNotStart: .loci("conversation.agentWouldNotStart")
      }
    return Text(joining: Text(verbatim: Agents.name(of: provider) + " "), Text(said))
  }
}

/// Beside the last bubble of a finished answer: copy all of it. Shows while the pointer is over the answer.
struct AnswerActions: View {
  let text: String
  let shown: Bool
  @Environment(\.showsCopyButtons) private var showsCopyButtons

  var body: some View {
    CopyButton { CopyButton.put(text) }
      .opacity(shown || showsCopyButtons ? 1 : 0)
  }
}

/// The question and its answer went into the highlight.
struct SavedChip: View {
  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: Symbols.done).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accentInk)
      Text(.loci("conversation.saved")).font(.system(size: 11.5)).foregroundStyle(Palette.inkMuted)
    }
    .frame(height: 24)
    .padding(.leading, 8)
    .padding(.trailing, 10)
    .background(Capsule().fill(Palette.tint))
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Where the conversation started over, between the messages.
struct StartedOverLine: View {
  var body: some View {
    HStack(spacing: Spacing.s) {
      Rectangle().fill(Palette.line).frame(height: Size.hairline)
      Text(.loci("conversation.startedOver")).fixedSize()
      Rectangle().fill(Palette.line).frame(height: Size.hairline)
    }
    .padding(.vertical, Spacing.xs)
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(Palette.inkFaint)
    .frame(maxWidth: .infinity)
  }
}
