import LociModel
import SwiftUI

/// A written lesson as plain text, with the items it draws on beside it.
struct LessonScreen: View {
  @Environment(\.host) private var host
  let lesson: LessonRef
  @State private var text = ""
  @State private var citations: [Citation] = []
  @State private var mentor: Feed<MentorPage>?
  @State private var items: Feed<[Item]>?

  var body: some View {
    LessonView(title: title, text: text, sources: sources)
      .subscribing(OneMentor(mentor: lesson.mentor), into: $mentor)
      .subscribing(AllItems(), into: $items)
      .task(id: lesson) {
        text = (try? await host.run(ReadLessonText(lesson: lesson))) ?? ""
        citations = (try? await host.run(LessonCitations(lesson: lesson))) ?? []
      }
  }

  private var title: String {
    let lessons = mentor?.value?.catalog?.chapters.flatMap(\.lessons) ?? []
    return lessons.first { $0.slug == lesson.lesson }?.title ?? lesson.lesson.description
  }

  private var sources: [Item] {
    let known = Dictionary((items?.value ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<EntityID>()
    return citations.compactMap { citation in
      guard seen.insert(citation.item).inserted else { return nil }
      return known[citation.item]
    }
  }
}

struct LessonView: View {
  let title: String
  let text: String
  let sources: [Item]

  var body: some View {
    ReadingView(text: text)
      .navigationTitle(Text(verbatim: title))
      .inspector(isPresented: .constant(!sources.isEmpty)) {
        List {
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
        .scrollContentBackground(.hidden)
        .background(Palette.raised)
        .tint(Palette.accent)
        .inspectorColumnWidth(Size.panelWidth)
      }
  }
}
