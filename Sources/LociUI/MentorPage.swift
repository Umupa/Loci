import LociModel
import SwiftUI

struct MentorScreen: View {
  let mentor: EntityID
  @State private var feed: Feed<MentorPage>?

  var body: some View {
    Group {
      if let page = feed?.value {
        MentorView(page: page)
      } else {
        Palette.canvas
      }
    }
    .subscribing(OneMentor(mentor: mentor), into: $feed)
  }
}

/// A mentor's catalog: chapters and their lessons. An empty catalog shows only the mentor.
struct MentorView: View {
  let page: MentorPage

  var body: some View {
    content
      .background(Palette.canvas)
      .navigationTitle(Text(verbatim: page.mentor.name))
  }

  @ViewBuilder private var content: some View {
    if let catalog = page.catalog, !catalog.chapters.isEmpty {
      List {
        ForEach(Array(catalog.chapters.enumerated()), id: \.offset) { _, chapter in
          Section {
            ForEach(chapter.lessons, id: \.slug) { lesson in
              LessonRow(lesson: lesson, mentor: page.mentor.id, written: page.writtenLessons.contains(lesson.slug))
                .listRowSeparator(.hidden)
            }
          } header: {
            Text(verbatim: chapter.title)
          }
        }
      }
      .scrollContentBackground(.hidden)
    } else if page.catalog == nil {
      Label {
        Text(.loci("mentor.catalogUnreadable"))
      } icon: {
        Image(systemName: Symbols.problem)
      }
      .foregroundStyle(Palette.accentInk)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      Avatar(mentor: page.mentor, size: Size.avatarLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct LessonRow: View {
  let lesson: Lesson
  let mentor: EntityID
  let written: Bool

  var body: some View {
    if written {
      NavigationLink(value: Page.lesson(LessonRef(mentor: mentor, lesson: lesson.slug))) {
        Text(verbatim: lesson.title).foregroundStyle(Palette.ink)
      }
    } else {
      Text(verbatim: lesson.title).foregroundStyle(Palette.inkMuted)
    }
  }
}
