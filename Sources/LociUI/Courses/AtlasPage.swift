import LociModel
import SwiftUI

/// A course's atlas: its gist, then the blocks Loci drew from the subject, then a dashed frame for each lesson
/// read whose part is still being added. A lesson's bead opens it.
struct AtlasPage: View {
  let shown: AtlasShown
  let open: (Lesson.ID) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.xxl) {
        AtlasInline.text(shown.atlas.gist, size: 28, serif: true, weight: .semibold, highlight: true)
          .foregroundStyle(Palette.ink)
          .lineSpacing(8)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.bottom, -Spacing.m)
        ForEach(Array(shown.atlas.blocks.enumerated()), id: \.offset) { _, block in
          AtlasBlockView(block: block)
        }
        if !shown.adding.isEmpty {
          VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(shown.adding) { AtlasAdding(lesson: $0) }
          }
        }
      }
      .frame(maxWidth: Size.atlasPage, alignment: .leading)
      .padding(.horizontal, Spacing.xxl)
      .padding(.top, 64).padding(.bottom, 96)
      .frame(maxWidth: .infinity)
    }
    .scrollIndicators(.never)
    .background(Palette.canvas)
    .environment(\.atlasLessons, shown.lessons)
    .environment(\.openAtlasLesson, OpenAtlasLesson(action: open))
  }
}
