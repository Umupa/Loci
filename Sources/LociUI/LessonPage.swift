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

  var body: some View {
    ContentReader(
      content: .lesson(page.lesson), title: page.title, markdown: page.text, glossary: page.glossary, previous: previous
    ) {
      if !sources.isEmpty {
        PanelLinks(title: Text(.loci("lesson.sources"))) {
          ForEach(sources, id: \.id) { item in
            NavigationLink(value: Page.item(item.id)) {
              Label {
                Text(verbatim: item.title)
              } icon: {
                Image(systemName: Symbols.kind(ItemKind(item.kind)))
              }
            }
          }
        }
      }
    }
  }
}
