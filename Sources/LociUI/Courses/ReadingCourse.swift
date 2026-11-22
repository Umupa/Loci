import LociModel
import SwiftUI

/// One course being read, kept current with it: it opens on its atlas when it has one; the lesson chosen is
/// opened — which counts it read, and has Loci write the next one when it is the last written — and its text
/// follows each rewrite.
struct ReadingCourse: View {
  @Environment(\.host) private var host
  @Environment(\.peekLink) private var peekLink
  @Environment(\.showFailure) private var showFailure
  @Environment(\.changesAllowed) private var changesAllowed
  let course: EntityID
  let back: () -> Void
  @State private var page: Feed<CoursePage>?
  @State private var spot: CourseSpot?
  @State private var text: Feed<String?>?
  @State private var draft: PassageDraft?

  var body: some View {
    Group {
      if let page = page?.value, let spot {
        CourseReader(
          shown: shown(page, spot: spot),
          actions: ReadingActions(
            back: back, choose: choose, openAtlas: { withAnimation(Motion.swap) { self.spot = .atlas } },
            writeNow: { lesson in
              run { () async throws(HostError) in _ = try await host.run(WriteLessonNow(course: course, lesson: lesson))
              }
            },
            openLink: { peekLink?($0) })
        ) {
          ConversationScreen(
            ref: .course(course), draft: $draft, lesson: spot.lesson, courseLessons: page.course.lessons)
        }
      } else {
        Palette.canvas
      }
    }
    .subscribing(WatchCourse(course), into: $page)
    .onChange(of: page?.value?.lessons.map(\.id), initial: true) {
      guard spot == nil, let page = page?.value else { return }
      if page.atlas != nil { spot = .atlas } else { choose(Self.opening(page)) }
    }
    .task(id: spot) {
      guard let current = spot?.lesson else { return }
      text = nil
      for await feed in host.subscribe(WatchLesson(course: course, lesson: current)) { text = feed }
    }
  }

  /// The lesson a course without an atlas opens on: the first written lesson not read yet, or else the first.
  static func opening(_ page: CoursePage) -> Lesson.ID? {
    page.lessons.first { $0.body == .written && !$0.isRead }?.id ?? page.firstReadableLesson ?? page.lessons.first?.id
  }

  private func choose(_ lesson: Lesson.ID?) {
    guard let lesson else { return }
    withAnimation(Motion.swap) { spot = .lesson(lesson) }
    run { () async throws(HostError) in _ = try await host.run(OpenLesson(course: course, lesson: lesson)) }
  }

  private func shown(_ page: CoursePage, spot: CourseSpot) -> ReadingShown {
    let writing = page.activity.writingLesson
    let lessons = page.lessons
    let current = spot.lesson
    let open = lessons.first { $0.id == current }
    let lesson: ShownLesson =
      if spot == .atlas, let atlas = AtlasShown(page, writing: writing) {
        .atlas(atlas)
      } else if let current, let open, open.body == .written, case .value(let markdown?) = text {
        .written(current, title: open.lesson.title, minutes: LessonFacts.minutes(markdown), markdown: markdown)
      } else if open?.body == .written, text == nil {
        .arriving
      } else if let current {
        .unwritten(current, title: open?.lesson.title ?? "", writing: writing == current)
      } else {
        .arriving
      }
    return ReadingShown(
      course: course, title: page.course.goal.title ?? page.course.title,
      lessons: lessons.map { row($0, current: current, writing: writing) },
      sources: page.course.sources.map { SourceShown($0, reading: false) }, lesson: lesson,
      hasAtlas: page.atlas != nil)
  }

  private func row(_ lesson: CourseLesson, current: Lesson.ID?, writing: Lesson.ID?) -> LessonThread.Row {
    let mark: LessonThread.Mark =
      lesson.id == writing ? .writing : lesson.body != .written ? .planned : lesson.isRead ? .read : .written
    return LessonThread.Row(id: lesson.id, title: lesson.lesson.title, mark: mark, current: lesson.id == current)
  }

  /// Sends what the person did, unless the Mac behind the window cannot take changes now.
  private func run(_ work: @escaping @MainActor () async throws(HostError) -> Void) {
    guard changesAllowed else { return }
    Task {
      do throws(HostError) {
        try await work()
      } catch {
        showFailure(error)
      }
    }
  }
}

/// Where a course being read is open: its atlas, or one of its lessons.
enum CourseSpot: Hashable {
  case atlas
  case lesson(Lesson.ID)

  var lesson: Lesson.ID? {
    if case .lesson(let lesson) = self { lesson } else { nil }
  }
}
