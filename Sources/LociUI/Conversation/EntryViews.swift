import LociModel
import SwiftUI

/// What the person said: a card on the right, with the passage it asks about above it.
struct AskedMessage: View {
  let prompt: Prompt
  let revealPassage: @MainActor (Locator) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      if let passage = prompt.passage {
        Button {
          revealPassage(passage.locator)
        } label: {
          QuotedLine(text: passage.excerpt)
        }
        .buttonStyle(.plain)
      }
      Text(verbatim: prompt.text)
        .font(.system(size: 14))
        .foregroundStyle(Palette.ink)
        .lineSpacing(3)
        .textSelection(.enabled)
    }
    .padding(.horizontal, 15)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous).fill(Palette.surface)
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.06), radius: 7, y: 4)
    )
    .containerRelativeFrame(.horizontal, alignment: .trailing) { width, _ in width * 0.88 }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .trailing)
  }
}

/// Quoted words in serif, behind a thin amber bar.
struct QuotedLine: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      RoundedRectangle(cornerRadius: 1).fill(Palette.accent.opacity(0.8)).frame(width: 2)
      Text(verbatim: text)
        .font(Typography.quote)
        .foregroundStyle(Palette.inkMuted)
        .lineSpacing(3)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .fixedSize(horizontal: false, vertical: true)
    .contentShape(Rectangle())
  }
}

/// The question and its answer went into the highlight.
struct SavedChip: View {
  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: Symbols.done).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent)
      Text(.loci("conversation.saved")).font(.system(size: 11.5)).foregroundStyle(Palette.inkMuted)
    }
    .frame(height: 24)
    .padding(.leading, 8)
    .padding(.trailing, 10)
    .background(Capsule().fill(Palette.tint))
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// What Loci asked for, or how a turn went, between the messages.
struct AsideLine: View {
  let message: Message

  var body: some View {
    Group {
      switch message.body {
      case .prompt(let prompt):
        switch prompt.purpose {
        case .writeLesson(let lesson):
          HStack(spacing: Spacing.xxs) {
            Text(.loci("conversation.writeLesson"))
            Text(verbatim: lesson.description).font(Typography.mono)
          }
        case .begin, .chat:
          Text(.loci("conversation.begin"))
        }
      case .notice(let text):
        Text(verbatim: text)
      case .ended(.interrupted):
        Text(.loci("conversation.stopped"))
      case .ended(.failed(let reason)):
        Label {
          Text(verbatim: reason)
        } icon: {
          Image(systemName: Symbols.problem)
        }
        .foregroundStyle(Palette.accentInk)
      case .reply, .thinking, .tool, .savedToNote:
        EmptyView()
      }
    }
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(Palette.inkFaint)
    .frame(maxWidth: .infinity)
    .multilineTextAlignment(.center)
  }
}
