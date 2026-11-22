import LociModel
import SwiftUI

/// One course being read, kept current with it: the lesson chosen is opened — which counts it read, and has Loci
/// write the next one when it is the last written — and its text follows each rewrite.
struct ReadingCourse: View {
  @Environment(\.host) private var host
  @Environment(\.peekLink) private var peekLink
  @Environment(\.showFailure) private var showFailure
  @Environment(\.changesAllowed) private var changesAllowed
  let course: EntityID
  let back: () -> Void
  @State private var page: Feed<CoursePage>?
  @State private var current: Lesson.ID?
  @State private var text: Feed<String?>?
  @State private var draft: PassageDraft?

  var body: some View {
    Group {
      if let page = page?.value, let current {
        CourseReader(
          shown: shown(page, current: current),
          actions: ReadingActions(
            back: back, choose: choose,
            writeNow: { lesson in
              run { () async throws(HostError) in _ = try await host.run(WriteLessonNow(course: course, lesson: lesson))
              }
            },
            openLink: { peekLink?($0) })
        ) {
          ConversationScreen(ref: .course(course), draft: $draft, lesson: current, courseLessons: page.course.lessons)
        }
      } else {
        Palette.canvas
      }
    }
    .subscribing(WatchCourse(course), into: $page)
    .onChange(of: page?.value?.lessons.map(\.id), initial: true) {
      if current == nil, let page = page?.value { choose(Self.opening(page)) }
    }
    .task(id: current) {
      guard let current else { return }
      text = nil
      for await feed in host.subscribe(WatchLesson(course: course, lesson: current)) { text = feed }
    }
  }

  /// Where a course opens: the first written lesson not read yet, or else the first lesson.
  static func opening(_ page: CoursePage) -> Lesson.ID? {
    page.lessons.first { $0.body == .written && !$0.isRead }?.id ?? page.firstReadableLesson ?? page.lessons.first?.id
  }

  private func choose(_ lesson: Lesson.ID?) {
    guard let lesson else { return }
    withAnimation(Motion.swap) { current = lesson }
    run { () async throws(HostError) in _ = try await host.run(OpenLesson(course: course, lesson: lesson)) }
  }

  private func shown(_ page: CoursePage, current: Lesson.ID) -> ReadingShown {
    let writing = page.activity.writingLesson
    let lessons = page.lessons
    let open = lessons.first { $0.id == current }
    let lesson: ShownLesson =
      if let open, open.body == .written, case .value(let markdown?) = text {
        .written(current, title: open.lesson.title, minutes: LessonFacts.minutes(markdown), markdown: markdown)
      } else if open?.body == .written, text == nil {
        .arriving
      } else {
        .unwritten(current, title: open?.lesson.title ?? "", writing: writing == current)
      }
    return ReadingShown(
      course: course, title: page.course.goal.title ?? page.course.title,
      lessons: lessons.map { row($0, current: current, writing: writing) },
      sources: page.course.sources.map { SourceShown($0, reading: false) }, lesson: lesson)
  }

  private func row(_ lesson: CourseLesson, current: Lesson.ID, writing: Lesson.ID?) -> LessonThread.Row {
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
