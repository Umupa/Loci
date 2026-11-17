import LociModel
import SwiftUI

/// A lesson in the reader, kept current as the mentor revises it, with the items it draws on beside it.
struct LessonScreen: View {
  @Environment(\.host) private var host
  let lesson: LessonRef
  @State private var page: Feed<LessonPage>?
  @State private var items: Feed<[Item]>?
  @State private var previous: String?

  var body: some View {
    Group {
      if let page = page?.value {
        LessonView(page: page, sources: sources(of: page), previous: previous)
      } else {
        Palette.canvas
      }
    }
    .subscribing(OneLesson(lesson: lesson), into: $page)
    .subscribing(AllItems(), into: $items)
    .onChange(of: page?.value?.text) {
      guard page?.value != nil else { return }
      Task {
        if let before = (try? await host.run(SeeLesson(lesson: lesson))) ?? nil { previous = before }
      }
    }
  }

  private func sources(of page: LessonPage) -> [Item] {
    let known = Dictionary((items?.value ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<EntityID>()
    return page.citations.compactMap { citation in
      guard seen.insert(citation.item).inserted else { return nil }
      return known[citation.item]
    }
  }
}

struct LessonView: View {
  let page: LessonPage
  let sources: [Item]
  /// The text the reader saw before the mentor's latest revision.
  let previous: String?
  @State private var ended = false

  var body: some View {
    ContentReader(
      content: .lesson(page.lesson), markdown: page.text, glossary: page.glossary, previous: previous,
      reachedEnd: { ended = true }
    ) {
      if !sources.isEmpty {
        Section {
          ForEach(sources, id: \.id) { item in
            NavigationLink(value: Page.item(item.id)) {
              Label {
                Text(verbatim: item.title)
              } icon: {
                Image(systemName: Symbols.kind(ItemKind(item.kind)))
              }
            }
          }
        } header: {
          Text(.loci("lesson.sources"))
        }
      }
    }
    .overlay(alignment: .bottom) {
      if ended, let next = page.next {
        NextLessonButton(mentor: page.lesson.mentor, next: next)
          .padding(.bottom, Spacing.l)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(Motion.standard, value: ended)
    .navigationTitle(Text(verbatim: page.title ?? page.lesson.lesson.description))
    .toolbar {
      if previous != nil {
        ToolbarItem {
          Label {
            Text(.loci("lesson.revised"))
          } icon: {
            Image(systemName: Symbols.lessonRevised)
          }
          .labelStyle(.titleAndIcon)
          .foregroundStyle(Palette.accentInk)
        }
      }
    }
  }
}

/// At the end of a lesson: go on to the next one, or ask the mentor to write it first.
struct NextLessonButton: View {
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  let mentor: EntityID
  let next: LessonPage.Upcoming
  @State private var asked = false

  var body: some View {
    Button(action: go) {
      HStack(spacing: Spacing.xs) {
        if asked && !next.written {
          ProgressView().controlSize(.small)
          Text(.loci("lesson.writing"))
        } else {
          Text(next.written ? .loci("lesson.next") : .loci("lesson.askNext"))
          Text(verbatim: next.lesson.title).fontWeight(.medium)
          Image(systemName: Symbols.nextLesson)
        }
      }
      .padding(.horizontal, Spacing.xs)
    }
    .buttonStyle(.glassProminent)
    .controlSize(.extraLarge)
    .tint(Palette.accent)
    .disabled(asked && !next.written)
  }

  private func go() {
    let ref = LessonRef(mentor: mentor, lesson: next.lesson.slug)
    if next.written {
      openPage(.lesson(ref), replacing: true)
    } else {
      asked = true
      Task {
        do throws(HostError) {
          _ = try await host.run(WriteLesson(lesson: ref))
        } catch {
          asked = false
        }
      }
    }
  }
}
