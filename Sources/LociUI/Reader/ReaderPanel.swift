import AppKit
import LociModel
import SwiftUI

/// The pages of the panel beside text.
enum PanelTab: Hashable {
  case contents, notes
}

/// Beside the text: its headings and whatever the page adds under them, or every note left on it.
struct ReaderPanel<Extra: View>: View {
  let content: ContentRef
  let headings: [ReadingText.Heading]
  let notes: [PlacedNote]
  let pending: [PendingAnswer]
  @Binding var tab: PanelTab
  /// The note whose margin mark was clicked last.
  let focusedNote: EntityID?
  let reveal: (NSRange) -> Void
  @ViewBuilder let extra: () -> Extra
  @State private var mentors: Feed<[Mentor]>?

  var body: some View {
    VStack(spacing: 0) {
      Picker(selection: $tab) {
        Text(.loci("panel.contents")).tag(PanelTab.contents)
        Text(.loci("panel.notes")).tag(PanelTab.notes)
      } label: {
        EmptyView()
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(Spacing.s)
      switch tab {
      case .contents: contents
      case .notes: notesList
      }
    }
    .background(Palette.raised)
    .subscribing(AllMentors(), into: $mentors)
  }

  private var contents: some View {
    List {
      if !headings.isEmpty {
        Section {
          ForEach(headings, id: \.offset) { heading in
            Button {
              reveal(NSRange(location: heading.offset, length: (heading.title as NSString).length))
            } label: {
              Text(verbatim: heading.title)
                .foregroundStyle(heading.level <= 2 ? Palette.ink : Palette.inkMuted)
                .padding(.leading, CGFloat(max(heading.level - 1, 0)) * Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
      extra()
    }
    .scrollContentBackground(.hidden)
  }

  private var notesList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Spacing.s) {
          ForEach(notes) { placed in
            NoteCard(
              content: content, placed: placed, pending: pending.filter { $0.note == placed.id },
              mentors: mentors?.value ?? [], focused: placed.id == focusedNote
            ) {
              if let range = placed.range { reveal(range) }
            }
            .id(placed.id)
          }
          ForEach(orphanAnswers, id: \.askedAt) { answer in
            AnswerView(
              question: answer.question, answer: answer.answer, mentor: mentor(answer.mentor), failure: answer.failure
            )
            .padding(Spacing.s)
          }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.bottom, Spacing.s)
      }
      .onChange(of: focusedNote) { _, note in
        if let note { withAnimation(Motion.standard) { proxy.scrollTo(note, anchor: .center) } }
      }
    }
  }

  /// Answers to questions whose note has not arrived yet.
  private var orphanAnswers: [PendingAnswer] {
    let known = Set(notes.map(\.id))
    return pending.filter { !known.contains($0.note) }
  }

  private func mentor(_ id: EntityID) -> Mentor? {
    mentors?.value?.first { $0.id == id }
  }
}
