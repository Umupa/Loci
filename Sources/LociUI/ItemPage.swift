import LociModel
import SwiftUI

struct ItemScreen: View {
  let item: EntityID
  @State private var feed: Feed<ItemPage>?

  var body: some View {
    Group {
      if let page = feed?.value {
        ItemView(page: page)
      } else {
        Palette.canvas
      }
    }
    .subscribing(OneItem(item: item), into: $feed)
  }
}

/// An item's text, with the lessons that cite it beside it.
struct ItemView: View {
  let page: ItemPage

  var body: some View {
    ReadingView(text: page.text ?? "")
      .navigationTitle(Text(verbatim: page.item.title))
      .inspector(isPresented: .constant(!citingLessons.isEmpty)) {
        List {
          Section {
            ForEach(citingLessons, id: \.citation.lesson) { citing in
              NavigationLink(value: Page.lesson(citing.citation.lesson)) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                  Text(verbatim: citing.lessonTitle ?? citing.citation.lesson.lesson.description)
                    .foregroundStyle(Palette.ink)
                  Text(verbatim: citing.mentorName)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                }
              }
            }
          } header: {
            Text(.loci("item.citedBy"))
          }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.raised)
        .tint(Palette.accent)
        .inspectorColumnWidth(Size.panelWidth)
      }
  }

  /// One row per lesson, however many places in the item it points to.
  private var citingLessons: [CitingLesson] {
    var seen = Set<LessonRef>()
    return page.citedBy.filter { seen.insert($0.citation.lesson).inserted }
  }
}
