import LociModel
import SwiftUI

/// The builder of one course, kept current with it: the course's own conversation on the left with Loci's open
/// question at its end, and each step and answer sent to the host.
struct BuildingCourse: View {
  @Environment(\.host) private var host
  @Environment(\.peekLink) private var peekLink
  @Environment(\.showFailure) private var showFailure
  @Environment(\.changesAllowed) private var changesAllowed
  let course: EntityID
  let newlyStarted: Bool
  let collapse: () -> Void
  /// Opens the course to read, at the lesson given.
  let read: (Lesson.ID?) -> Void
  @State private var page: Feed<CoursePage>?
  @State private var minutes: [Lesson.ID: Int] = [:]
  @State private var lastWritten: (id: Lesson.ID, markdown: String)?
  @State private var draft: PassageDraft?

  var body: some View {
    Group {
      if let page = page?.value {
        CourseBuilder(
          shown: BuilderShown(page, minutes: minutes, shownLesson: lastWritten), actions: actions(page),
          newlyStarted: newlyStarted
        ) {
          ConversationScreen(ref: .course(course), draft: $draft, courseLessons: page.course.lessons) {
            if let question = page.course.question { QuestionTail(question: question) }
          }
        }
      } else {
        RoundedRectangle(cornerRadius: Radius.builder, style: .continuous).fill(Palette.builderFace)
      }
    }
    .subscribing(WatchCourse(course), into: $page)
    .task(id: writtenLessons) { await measure() }
    .task(id: writtenLessons.last) {
      guard let last = writtenLessons.last else { return }
      for await feed in host.subscribe(WatchLesson(course: course, lesson: last)) {
        if case .value(let markdown?) = feed { lastWritten = (last, markdown) }
      }
    }
  }

  private var writtenLessons: [Lesson.ID] {
    (page?.value?.lessons ?? []).filter { $0.body == .written }.map(\.id)
  }

  /// Works out how long each lesson written takes to read, once.
  private func measure() async {
    for lesson in writtenLessons where minutes[lesson] == nil {
      if let markdown = try? await host.run(ReadLesson(course: course, lesson: lesson)) {
        minutes[lesson] = LessonFacts.minutes(markdown)
      }
    }
  }

  private func actions(_ page: CoursePage) -> BuilderActions {
    BuilderActions(
      answer: { question, answer in
        run { () async throws(HostError) in
          _ = try await host.run(AnswerCourseQuestion(course: course, question: question.id, answer: answer))
        }
      },
      goOn: {
        switch page.course.stage {
        case .goal: run { () async throws(HostError) in _ = try await host.run(BeginCourseSources(course)) }
        case .sources: run { () async throws(HostError) in _ = try await host.run(BeginCourseWriting(course)) }
        case .writing: read(page.firstReadableLesson)
        }
      },
      collapse: collapse,
      strike: { source in
        run { () async throws(HostError) in
          _ = try await host.run(RemoveCourseSource(course: course, source: source.id))
        }
      },
      addSource: { url in
        run { () async throws(HostError) in _ = try await host.run(AddCourseSource(course: course, url: url)) }
      },
      openSource: { peekLink?($0) })
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
