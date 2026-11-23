import LociModel
import SwiftUI

/// Everything the reading page draws of a course.
struct ReadingShown: Equatable {
  let course: EntityID
  let title: String
  var lessons: [LessonThread.Row]
  var sources: [SourceShown]
  var lesson: ShownLesson
  /// Whether the course has an atlas to open from the contents.
  var hasAtlas = false

  var atlasOpen: Bool {
    if case .atlas = lesson { true } else { false }
  }
}

/// What the person does on the reading page.
struct ReadingActions {
  var back: () -> Void = {}
  var choose: (Lesson.ID) -> Void = { _ in }
  var openAtlas: () -> Void = {}
  var writeNow: (Lesson.ID) -> Void = { _ in }
  var openLink: (URL) -> Void = { _ in }
}

/// Reading a course: its lessons and sources on the left, and the open lesson in the reader the articles are read
/// in — a thin amber line along the top for how far down it has been read, highlights, and Loci in the panel
/// beside it. Beside a lesson not written yet is the course's conversation. The contents fold away, and where
/// the window leaves the lesson too little room they and the panel lie over it when asked for instead.
struct CourseReader<Conversation: View>: View {
  @Environment(\.lociFace) private var face
  @Environment(\.locale) private var locale
  let shown: ReadingShown
  let actions: ReadingActions
  var pointedSource: EntityID?
  /// The course's conversation, beside a lesson not written yet.
  @ViewBuilder let conversation: () -> Conversation
  @AppStorage(PanelMemory.key) private var panelShown = PanelMemory.shownAtFirst
  @AppStorage(CourseNav.key) private var navShown = true
  /// The contents laid over the lesson, asked for where there is no room for them beside it.
  @State private var navFloating = false
  @State private var panelFloating = false
  @State private var width = CGFloat.infinity

  var body: some View {
    let navBeside = CourseNav.fitsBeside(in: width)
    HStack(spacing: 0) {
      if navShown, navBeside {
        nav.transition(.move(edge: .leading).combined(with: .opacity))
      }
      lesson(room: navShown && navBeside ? width - CourseNav.width : width)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Palette.canvas)
    .overlay(alignment: .leading) {
      if navFloating, !navBeside {
        nav
          .frame(maxHeight: .infinity, alignment: .top)
          .background(Palette.canvas)
          .overlay(alignment: .trailing) { Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline) }
          .shadow(color: Palette.warmShadow.opacity(0.22), radius: 24, x: 10)
          .transition(.move(edge: .leading))
      }
    }
    .windowCorner([
      WindowCornerItem(
        symbol: Symbols.back, label: .loci("course.back"), shortcut: KeyboardShortcut("[")
      ) { actions.back() },
      WindowCornerItem(symbol: Symbols.contents, label: .loci("course.contents")) {
        withAnimation(Motion.fold) {
          if navBeside { navShown.toggle() } else { navFloating.toggle() }
        }
      },
    ])
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
  }

  private var nav: some View {
    CourseNav(
      title: shown.title, lessons: shown.lessons, sources: shown.sources, pointedSource: pointedSource,
      atlas: shown.hasAtlas ? CourseNav.AtlasRow(open: shown.atlasOpen) : nil,
      choose: { lesson in
        withAnimation(Motion.fold) { navFloating = false }
        actions.choose(lesson)
      },
      openAtlas: {
        withAnimation(Motion.fold) { navFloating = false }
        actions.openAtlas()
      },
      openSource: actions.openLink)
  }

  @ViewBuilder private func lesson(room: CGFloat) -> some View {
    switch shown.lesson {
    case .written(let lesson, let title, let minutes, let markdown):
      let sources = shown.sources.compactMap(\.url)
      ContentReader(
        content: .lesson(course: shown.course, lesson: lesson), title: title, markdown: markdown,
        byline: LessonFacts.byline(face: face, minutes: minutes, locale: locale),
        cite: { LessonFacts.citation(of: $0, in: sources) }, showsProgress: true
      )
      .id(lesson)
      .transition(.opacity)
    case .atlas(let atlas):
      beside(room: room) {
        AtlasPage(shown: atlas, open: actions.choose)
      }
      .id("atlas")
      .transition(.opacity)
    case .unwritten(let lesson, let title, let writing):
      beside(room: room) {
        UnwrittenLesson(title: title, writing: writing) { actions.writeNow(lesson) }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .id(lesson)
      .transition(.opacity)
    case .arriving:
      Palette.canvas
    }
  }

  private func expandPanel() {
    withAnimation(Motion.fold) {
      panelShown = true
      panelFloating = true
    }
  }

  /// `content` with the course's conversation in the panel beside it, folded away where there is no room.
  @ViewBuilder private func beside(room: CGFloat, @ViewBuilder content: @escaping () -> some View) -> some View {
    let beside = PaneWidth.panel.fitsBeside(in: room)
    SidePanel(
      open: beside ? panelShown : panelFloating, beside: beside, width: min(Size.mediaPanel, room),
      expand: expandPanel
    ) {
      content()
    } panel: {
      CoursePanel(
        collapse: {
          withAnimation(Motion.fold) {
            if beside { panelShown = false }
            panelFloating = false
          }
        }, conversation: conversation)
    }
  }
}

/// The course's conversation beside the atlas or a lesson not written yet, under the button that folds it away.
struct CoursePanel<Conversation: View>: View {
  let collapse: () -> Void
  @ViewBuilder let conversation: () -> Conversation

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer(minLength: 0)
        PanelButton(title: .loci("panel.collapse"), action: collapse)
      }
      .padding(.horizontal, Spacing.s)
      .frame(height: 52)
      conversation()
    }
    .background(Palette.canvas)
  }
}
