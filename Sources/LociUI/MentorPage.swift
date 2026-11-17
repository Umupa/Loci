import LociModel
import SwiftUI

/// What a mentor's page shows: its catalog, or the conversation with it.
enum MentorTab: Hashable {
  case catalog, conversation
}

struct MentorScreen: View {
  @Environment(\.host) private var host
  let mentor: EntityID
  @State private var feed: Feed<MentorPage>?
  @State private var conversation: Feed<Conversation>?
  @State private var tab = MentorTab.catalog

  var body: some View {
    Group {
      if let page = feed?.value {
        switch tab {
        case .catalog:
          MentorView(page: page, turn: conversation?.value?.turn) { lesson in
            Task { _ = try? await host.run(WriteLesson(lesson: LessonRef(mentor: mentor, lesson: lesson.slug))) }
          }
        case .conversation:
          ConversationScreen(mentor: page.mentor, conversation: conversation?.value)
            .navigationTitle(Text(verbatim: page.mentor.name))
        }
      } else {
        Palette.canvas
      }
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker(selection: $tab) {
          Text(.loci("mentor.catalog")).tag(MentorTab.catalog)
          Text(.loci("mentor.conversation")).tag(MentorTab.conversation)
        } label: {
          EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
    }
    .subscribing(OneMentor(mentor: mentor), into: $feed)
    .subscribing(MentorConversation(mentor: mentor), into: $conversation)
  }
}

/// A mentor's catalog as a tree of chapters and lessons, each lesson marked read, revised or not yet
/// written. While the mentor works, what it is doing shows above the catalog, or alone until a catalog exists.
struct MentorView: View {
  let page: MentorPage
  let turn: LiveTurn?
  let write: (Lesson) -> Void

  var body: some View {
    content
      .background(Palette.canvas)
      .navigationTitle(Text(verbatim: page.mentor.name))
  }

  @ViewBuilder private var content: some View {
    if let catalog = page.catalog, !catalog.chapters.isEmpty {
      CatalogTree(page: page, catalog: catalog, write: write, mentorBusy: turn != nil)
        .safeAreaBar(edge: .top) {
          if let turn {
            ActivityLine(turn: turn)
              .padding(.horizontal, Spacing.l)
              .padding(.vertical, Spacing.xs)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
    } else if page.catalog == nil {
      Label {
        Text(.loci("mentor.catalogUnreadable"))
      } icon: {
        Image(systemName: Symbols.problem)
      }
      .foregroundStyle(Palette.accentInk)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(spacing: Spacing.l) {
        Avatar(mentor: page.mentor, size: Size.avatarLarge)
        if let turn { ActivityLine(turn: turn) }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct CatalogTree: View {
  let page: MentorPage
  let catalog: Catalog
  let write: (Lesson) -> Void
  let mentorBusy: Bool
  @State private var folded: Set<Int> = []

  var body: some View {
    List {
      ForEach(Array(catalog.chapters.enumerated()), id: \.offset) { index, chapter in
        Section(isExpanded: expanded(index)) {
          ForEach(chapter.lessons, id: \.slug) { lesson in
            LessonRow(
              lesson: lesson, mentor: page.mentor.id, mark: mark(of: lesson.slug), mentorBusy: mentorBusy,
              write: { write(lesson) }
            )
            .listRowSeparator(.hidden)
          }
        } header: {
          Text(verbatim: chapter.title)
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func expanded(_ chapter: Int) -> Binding<Bool> {
    Binding(
      get: { !folded.contains(chapter) },
      set: { if $0 { folded.remove(chapter) } else { folded.insert(chapter) } })
  }

  private func mark(of slug: Lesson.Slug) -> LessonMark {
    guard page.writtenLessons.contains(slug) else { return .unwritten }
    if page.revisedLessons.contains(slug) { return .revised }
    return page.readLessons.contains(slug) ? .read : .unread
  }
}

/// Where a lesson stands for the reader.
enum LessonMark {
  case unwritten, unread, read
  /// Written, and changed by the mentor since the reader last saw it.
  case revised

  var symbol: String {
    switch self {
    case .unwritten: Symbols.lessonUnwritten
    case .unread: Symbols.lessonUnread
    case .read: Symbols.lessonRead
    case .revised: Symbols.lessonRevised
    }
  }
}

private struct LessonRow: View {
  let lesson: Lesson
  let mentor: EntityID
  let mark: LessonMark
  let mentorBusy: Bool
  let write: () -> Void
  @State private var hovering = false

  var body: some View {
    if mark == .unwritten {
      HStack(spacing: Spacing.xs) {
        symbol
        Text(verbatim: lesson.title).foregroundStyle(Palette.inkMuted)
        Spacer(minLength: Spacing.s)
        if hovering && !mentorBusy {
          Button(action: write) {
            Text(.loci("lesson.write"))
          }
          .buttonStyle(.borderless)
          .foregroundStyle(Palette.accentInk)
        }
      }
      .contentShape(Rectangle())
      .onHover { hovering = $0 }
    } else {
      NavigationLink(value: Page.lesson(LessonRef(mentor: mentor, lesson: lesson.slug))) {
        HStack(spacing: Spacing.xs) {
          symbol
          Text(verbatim: lesson.title).foregroundStyle(Palette.ink)
        }
      }
      .accessibilityValue(mark == .revised ? Text(.loci("lesson.revised")) : Text(verbatim: ""))
    }
  }

  private var symbol: some View {
    Image(systemName: mark.symbol)
      .foregroundStyle(mark == .revised ? Palette.accent : Palette.inkMuted)
      .frame(width: Size.avatarSmall)
      .accessibilityHidden(true)
  }
}

/// What the mentor is doing right now: the kind of work and what it works on.
struct ActivityLine: View {
  let turn: LiveTurn

  var body: some View {
    HStack(spacing: Spacing.xs) {
      ProgressView().controlSize(.small)
      Text(verb).foregroundStyle(Palette.inkMuted)
      if let subject {
        Text(verbatim: subject).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
      }
    }
    .font(Typography.body)
  }

  private var tool: ToolActivity? {
    turn.latestTool.flatMap { $0.state == .running ? $0 : nil }
  }

  private var verb: LocalizedStringResource {
    switch tool?.kind {
    case .read: .loci("activity.read")
    case .edit: .loci("activity.edit")
    case .execute: .loci("activity.execute")
    case .search: .loci("activity.search")
    case .other, nil: .loci("activity.thinking")
    }
  }

  /// A path is shown by its file name; a command or query as written.
  private var subject: String? {
    guard let tool, let subject = tool.subject else { return nil }
    return tool.kind == .read || tool.kind == .edit ? subject.split(separator: "/").last.map(String.init) : subject
  }
}
