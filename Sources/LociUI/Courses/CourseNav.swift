import LociModel
import SwiftUI

/// The reading page's left column: the course's small cover and name, its lessons on the thread, and the
/// sources it was written from.
struct CourseNav: View {
  let title: String
  let lessons: [LessonThread.Row]
  let sources: [SourceShown]
  var pointedSource: EntityID?
  let choose: (Lesson.ID) -> Void
  let openSource: (URL) -> Void

  /// Where this Mac keeps whether the contents are shown beside the lesson.
  static let key = "courseContentsShown"
  /// How wide the column is.
  static let width = Size.courseNav + 26 + Spacing.m

  /// Whether the column fits beside a lesson in `available` points and leaves the lesson room to be read.
  static func fitsBeside(in available: CGFloat) -> Bool {
    available - width >= Size.readerMinimum
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: Spacing.s) {
          ClothBook(title: title, subtitle: "", read: 0, lettered: false)
            .frame(width: 44)
            .shadow(color: Palette.warmShadow.opacity(0.4), radius: 6, y: 5)
          Text(serif: title, Serif.Face(size: 17, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
        }
        .padding(.bottom, Spacing.l)
        LessonThread(lessons: lessons, ink: .window, rowHeight: 32, choose: choose)
        if !sources.isEmpty {
          Text(.loci("course.stageSources"))
            .font(Typography.sectionLabel)
            .foregroundStyle(Palette.inkFaint)
            .padding(.top, 26).padding(.bottom, 6).padding(.leading, 2)
          ForEach(sources) { source in
            SourceRow(source: source, pointed: pointedSource == source.id) {
              if let url = source.url { openSource(url) }
            }
          }
        }
      }
      .frame(width: Size.courseNav, alignment: .leading)
      .padding(.leading, 26).padding(.trailing, Spacing.m).padding(.top, 58).padding(.bottom, Spacing.l)
    }
    .scrollIndicators(.never)
  }
}

/// A source in the reading page's left column: its site's mark and its title, and under the pointer an arrow
/// saying it opens elsewhere.
private struct SourceRow: View {
  let source: SourceShown
  let pointed: Bool
  let open: () -> Void
  @State private var hovering = false

  var body: some View {
    let lit = hovering || pointed
    Button(action: open) {
      HStack(spacing: 9) {
        SiteBadge(site: source.url?.absoluteString ?? source.detail, size: 16, ring: .clear)
        Text(verbatim: source.title)
          .font(.system(size: 12.5))
          .foregroundStyle(Palette.ink.opacity(0.72))
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 0)
        Image(systemName: "arrow.up.right")
          .font(.system(size: 9.5, weight: .semibold))
          .foregroundStyle(Palette.inkMuted)
          .opacity(lit ? 1 : 0)
      }
      .padding(.horizontal, 6)
      .frame(height: 30)
      .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(lit ? Palette.fill : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.leading, -6)
    .onHover { hovering = $0 }
    .animation(Motion.quick, value: lit)
    .help(Text(verbatim: source.url?.absoluteString ?? source.title))
  }
}
