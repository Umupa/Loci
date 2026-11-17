import LociModel
import SwiftUI

/// A course in the sidebar: choosing it opens its current lesson; on hover a chevron folds its lessons open.
struct SidebarCourse: View {
  let mentor: Mentor
  /// The lesson of this course on screen, if any.
  let open: Lesson.Slug?
  @Binding var expanded: Bool
  let go: (Place) -> Void
  @State private var feed: Feed<MentorPage>?
  @State private var hovering = false

  var body: some View {
    let course = feed?.value.map { Course(page: $0, open: open) }
    SidebarRow(
      selected: open != nil, title: Text(verbatim: course?.title ?? mentor.request ?? mentor.name),
      icon: CourseMark(mentor: mentor, size: Size.avatarSmall),
      trailing: fold.opacity(hovering && course?.lessons.isEmpty == false ? 1 : 0)
    ) {
      go(course?.destination ?? .mentor(mentor.id))
    }
    .onHover { hovering = $0 }
    .subscribing(OneMentor(mentor: mentor.id), into: $feed)
    if expanded, let course {
      ForEach(course.lessons, id: \.lesson.slug) { entry in
        LessonRow(entry: entry, selected: entry.lesson.slug == open) {
          go(.lesson(LessonRef(mentor: mentor.id, lesson: entry.lesson.slug)))
        }
      }
    }
  }

  private var fold: some View {
    Button {
      withAnimation(Motion.fold) { expanded.toggle() }
    } label: {
      Image(systemName: Symbols.fold)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Palette.inkFaint)
        .rotationEffect(.degrees(expanded ? 90 : 0))
        .frame(width: Spacing.m, height: Spacing.m)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(expanded ? .loci("sidebar.collapse") : .loci("sidebar.expand")))
  }
}

/// One lesson under its course, with a glyph for how far the reader is.
private struct LessonRow: View {
  let entry: Course.Entry
  let selected: Bool
  let choose: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: choose) {
      HStack(spacing: Spacing.xs) {
        LessonGlyph(state: entry.state)
        Text(verbatim: entry.lesson.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
      }
      .font(Typography.lessonRow)
      .fontWeight(selected ? .semibold : .regular)
      .foregroundStyle(color)
      .padding(.horizontal, Spacing.xs)
      .frame(height: Size.lessonRowHeight)
      .background(
        RoundedRectangle(cornerRadius: Radius.small).fill(
          selected ? Palette.tint : hovering && entry.state != .unwritten ? Palette.fill : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .disabled(entry.state == .unwritten)
    .onHover { hovering = $0 }
    .padding(.leading, Spacing.m + 2)
    .listRowInsets(EdgeInsets())
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var color: Color {
    switch entry.state {
    case _ where selected: Palette.ink
    case .unwritten: Palette.inkFaint
    case .read, .current, .unread: Palette.sidebarInkMuted
    }
  }
}

/// Read is a filled check, current an amber ring with a dot, unread an open ring, unwritten a dashed ring.
struct LessonGlyph: View {
  let state: Course.State

  var body: some View {
    ZStack {
      switch state {
      case .read:
        Circle().fill(Palette.inkFaint).padding(0.8)
        Image(systemName: Symbols.done).font(.system(size: 6.5, weight: .heavy)).foregroundStyle(Palette.canvas)
      case .current:
        Circle().strokeBorder(Palette.accent, lineWidth: 1.2).padding(0.4)
        Circle().fill(Palette.accent).padding(3.4)
      case .unread:
        Circle().strokeBorder(Palette.inkFaint, lineWidth: 1.2).padding(0.8)
      case .unwritten:
        Circle().strokeBorder(Palette.inkFaint, style: StrokeStyle(lineWidth: 1.2, dash: [1.6, 2.1])).padding(0.8)
          .opacity(0.7)
      }
    }
    .frame(width: Size.lessonGlyph, height: Size.lessonGlyph)
    .accessibilityHidden(true)
  }
}
