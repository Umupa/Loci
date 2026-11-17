import LociModel
import SwiftUI

/// One message of a conversation, drawn by what kind it is.
struct MessageRow: View {
  let mentor: Mentor
  let message: Message
  let answer: (PermissionAsk, PermissionAsk.Answer) async -> Void

  var body: some View {
    switch message.body {
    case .prompt(let prompt):
      PromptRow(prompt: prompt)
    case .reply(let text):
      HStack(alignment: .top, spacing: Spacing.s) {
        Avatar(mentor: mentor, size: Size.avatarMedium)
        Text(Self.markdown(text))
          .font(Typography.reading)
          .lineSpacing(Typography.readingLineSpacing / 2)
          .foregroundStyle(Palette.ink)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    case .thinking(let text):
      ThinkingRow(text: text)
    case .tool(let tool):
      ToolCard(tool: tool)
    case .permission(let ask):
      PermissionCard(ask: ask, answer: answer)
    case .notice(let text):
      Text(verbatim: text).font(Typography.caption).foregroundStyle(Palette.inkMuted)
        .frame(maxWidth: .infinity)
    case .ended(.interrupted):
      Text(.loci("conversation.stopped")).font(Typography.caption).foregroundStyle(Palette.inkMuted)
        .frame(maxWidth: .infinity)
    case .ended(.failed(let reason)):
      Label {
        Text(verbatim: reason)
      } icon: {
        Image(systemName: Symbols.problem)
      }
      .font(Typography.body)
      .foregroundStyle(Palette.accentInk)
    }
  }

  /// Inline Markdown only: emphasis, code and links. Text that is not valid Markdown shows as written.
  static func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(
      markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(text)
  }
}

private struct PromptRow: View {
  let prompt: Prompt

  var body: some View {
    switch prompt.purpose {
    case .chat:
      Text(verbatim: prompt.text)
        .font(Typography.reading)
        .foregroundStyle(Palette.onSelection)
        .textSelection(.enabled)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Palette.selection))
        .frame(maxWidth: .infinity, alignment: .trailing)
    case .begin:
      Text(.loci("conversation.begin")).font(Typography.caption).foregroundStyle(Palette.inkMuted)
        .frame(maxWidth: .infinity)
    case .writeLesson(let lesson):
      HStack(spacing: Spacing.xxs) {
        Text(.loci("conversation.writeLesson"))
        Text(verbatim: lesson.description)
      }
      .font(Typography.caption)
      .foregroundStyle(Palette.inkMuted)
      .frame(maxWidth: .infinity)
    }
  }
}

private struct ThinkingRow: View {
  let text: String
  @State private var open = false

  var body: some View {
    DisclosureGroup(isExpanded: $open) {
      Text(verbatim: text).font(Typography.body).foregroundStyle(Palette.inkMuted).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text(.loci("conversation.thinking")).font(Typography.caption).foregroundStyle(Palette.inkMuted)
    }
  }
}

/// A tool the mentor ran: what kind, what on, whether it worked, and what it printed when opened.
struct ToolCard: View {
  let tool: ToolActivity
  @State private var open = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Button {
        open.toggle()
      } label: {
        HStack(spacing: Spacing.xs) {
          Image(systemName: Symbols.tool(tool.kind)).foregroundStyle(Palette.inkMuted).frame(width: Size.avatarSmall)
          Text(verbatim: tool.subject ?? tool.name).font(Typography.mono).foregroundStyle(Palette.ink)
            .lineLimit(1).truncationMode(.middle)
          Spacer(minLength: Spacing.xs)
          state
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(tool.output.isEmpty)
      if open && !tool.output.isEmpty {
        ScrollView {
          Text(verbatim: tool.output).font(Typography.mono).foregroundStyle(Palette.inkMuted)
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: Size.toolOutputHeight)
      }
    }
    .padding(.horizontal, Spacing.s)
    .padding(.vertical, Spacing.xs)
    .background(RoundedRectangle(cornerRadius: Radius.card).fill(Palette.raised))
  }

  @ViewBuilder private var state: some View {
    switch tool.state {
    case .running: ProgressView().controlSize(.mini)
    case .succeeded: Image(systemName: Symbols.done).foregroundStyle(Palette.inkMuted)
    case .failed: Image(systemName: Symbols.problem).foregroundStyle(Palette.accentInk)
    }
  }
}

/// The mentor asks before going on. Waiting cards offer the answers; answered ones say what was chosen.
struct PermissionCard: View {
  let ask: PermissionAsk
  let answer: (PermissionAsk, PermissionAsk.Answer) async -> Void
  @State private var sending = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.s) {
      Label {
        Text(verbatim: ask.title).foregroundStyle(Palette.ink)
      } icon: {
        Image(systemName: Symbols.permission).foregroundStyle(Palette.accentInk)
      }
      .font(Typography.bodyEmphasis)
      if let given = ask.answer {
        Text(given == .dismissed ? .loci("permission.dismissed") : label(of: chosen(given)))
          .font(Typography.caption)
          .foregroundStyle(Palette.inkMuted)
      } else {
        HStack(spacing: Spacing.xs) {
          ForEach(ask.options, id: \.id) { option in
            Button {
              sending = true
              Task {
                await answer(ask, .chosen(option.id))
                sending = false
              }
            } label: {
              Text(label(of: option))
            }
            .buttonStyle(.bordered)
            .tint(option.role == .allow || option.role == .allowAlways ? Palette.accent : nil)
            .disabled(sending)
          }
        }
      }
    }
    .padding(Spacing.s)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Radius.card).fill(Palette.surface))
    .overlay(
      RoundedRectangle(cornerRadius: Radius.card).strokeBorder(
        ask.answer == nil ? Palette.accent : Palette.line, lineWidth: 1))
  }

  private func chosen(_ answer: PermissionAsk.Answer) -> PermissionAsk.Option? {
    guard case .chosen(let id) = answer else { return nil }
    return ask.options.first { $0.id == id }
  }

  private func label(of option: PermissionAsk.Option?) -> LocalizedStringResource {
    guard let option else { return .loci("permission.dismissed") }
    if let label = option.label { return LocalizedStringResource(stringLiteral: label) }
    return switch option.role {
    case .allow: .loci("permission.allow")
    case .allowAlways: .loci("permission.allowAlways")
    case .deny: .loci("permission.deny")
    case .denyAlways: .loci("permission.denyAlways")
    case .choice: .loci("permission.choice")
    }
  }
}
