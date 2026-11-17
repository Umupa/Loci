import LociModel
import SwiftUI

/// One note in the panel: the words it marks, the thought, and each question with its answer.
struct NoteCard: View {
  @Environment(\.host) private var host
  let content: ContentRef
  let placed: PlacedNote
  let pending: [PendingAnswer]
  let mentors: [Mentor]
  let focused: Bool
  let select: () -> Void
  @State private var editing: Editing?
  @State private var draft = ""

  enum Editing {
    case thought, question
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      excerpt
      if let thought = placed.note.thought, editing != .thought {
        Text(verbatim: thought).foregroundStyle(Palette.ink)
      }
      ForEach(Array(placed.note.exchanges.enumerated()), id: \.offset) { _, exchange in
        AnswerView(
          question: exchange.question, answer: exchange.answer, mentor: mentor(exchange.mentor), failure: nil)
      }
      ForEach(pending, id: \.askedAt) { answer in
        AnswerView(
          question: answer.question, answer: answer.answer, mentor: mentor(answer.mentor), failure: answer.failure)
      }
      if let editing { field(editing) }
    }
    .font(Typography.body)
    .textSelection(.enabled)
    .padding(Spacing.s)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Radius.card).fill(focused ? Palette.selection.opacity(0.5) : Palette.surface)
    )
    .contentShape(RoundedRectangle(cornerRadius: Radius.card))
    .onTapGesture(perform: select)
    .contextMenu { menu }
  }

  private var excerpt: some View {
    HStack(alignment: .top, spacing: Spacing.xs) {
      RoundedRectangle(cornerRadius: 1).fill(placed.range == nil ? Palette.line : Palette.accent).frame(width: 2)
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(verbatim: placed.note.excerpt ?? placed.note.locator.quote?.text ?? "")
          .foregroundStyle(Palette.inkMuted)
          .lineLimit(3)
        if placed.range == nil {
          Label {
            Text(.loci("note.lost"))
          } icon: {
            Image(systemName: Symbols.problem)
          }
          .font(Typography.caption)
          .foregroundStyle(Palette.accentInk)
        }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder private var menu: some View {
    Button {
      draft = placed.note.thought ?? ""
      editing = .thought
    } label: {
      Text(placed.note.thought == nil ? .loci("note.writeThought") : .loci("note.editThought"))
    }
    if case .lesson = content, placed.range != nil {
      Button {
        draft = ""
        editing = .question
      } label: {
        Text(.loci("note.askAgain"))
      }
    }
    Button(role: .destructive) {
      Task { _ = try? await host.run(DeleteNote(content: content, note: placed.id)) }
    } label: {
      Text(.loci("note.delete"))
    }
  }

  private func field(_ editing: Editing) -> some View {
    TextField(text: $draft, axis: .vertical) {
      Text(editing == .thought ? .loci("passage.thoughtPrompt") : .loci("passage.questionPrompt"))
    }
    .textFieldStyle(.plain)
    .lineLimit(1...6)
    .onSubmit { submit(editing) }
    .onExitCommand { self.editing = nil }
  }

  private func submit(_ editing: Editing) {
    let text = draft
    self.editing = nil
    Task {
      switch editing {
      case .thought:
        _ = try? await host.run(SetNoteThought(content: content, note: placed.id, thought: text))
      case .question:
        guard case .lesson(let lesson) = content, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        _ = try? await host.run(
          AskAboutPassage(
            mentor: lesson.mentor, locator: placed.note.locator, excerpt: placed.note.excerpt, question: text,
            note: placed.id))
      }
    }
  }

  private func mentor(_ id: EntityID) -> Mentor? {
    mentors.first { $0.id == id }
  }
}

/// A question and the mentor's answer, which may still be arriving or may have failed.
struct AnswerView: View {
  let question: String
  let answer: String
  let mentor: Mentor?
  let failure: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(verbatim: question).font(Typography.bodyEmphasis).foregroundStyle(Palette.ink)
      HStack(alignment: .top, spacing: Spacing.xs) {
        if let mentor { Avatar(mentor: mentor, size: Size.avatarSmall) }
        if let failure {
          Label {
            Text(verbatim: failure)
          } icon: {
            Image(systemName: Symbols.problem)
          }
          .foregroundStyle(Palette.accentInk)
        } else if answer.isEmpty {
          ProgressView().controlSize(.small)
        } else {
          RichText(markdown: answer, font: Typography.body)
        }
      }
    }
  }
}
