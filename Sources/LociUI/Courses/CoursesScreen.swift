import LociModel
import SwiftUI

/// The courses page in the window: the gallery and the builder over it, or the course `open` names being read.
/// A course still being built opens in the builder; one already read opens to read.
struct CoursesScreen: View {
  @Environment(\.host) private var host
  @Environment(\.openPlace) private var openPlace
  @Environment(\.showFailure) private var showFailure
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.deletions) private var deletions
  @Environment(\.undoManager) private var undoManager
  let open: EntityID?
  @State private var courses: Feed<[CourseEntry]>?
  @State private var building: EntityID?
  @State private var origin = GrowthOrigin.wish
  @State private var started: EntityID?
  @State private var bumped: Bump?
  @State private var wish = ""

  var body: some View {
    Group {
      if let open {
        ReadingCourse(course: open) { openPlace(.courses(nil)) }
      } else {
        CoursesLayout(
          books: books, building: building,
          builder: { course in
            BuildingCourse(
              course: course, newlyStarted: course == started, collapse: { collapse(course) },
              read: { lesson in read(course, from: lesson) })
          }, origin: origin, bumped: bumped, wish: $wish, start: start, open: choose, delete: delete
        )
        .overlay(alignment: .bottom) {
          if let deletion = deletions?.latest {
            DeletedNotice(words: deletion.words) { deletions?.undo() }
              .padding(.bottom, 20)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .animation(Motion.standard, value: deletions?.latest)
        .task(id: deletions?.latest) {
          guard let deletion = deletions?.latest else { return }
          try? await Task.sleep(for: .seconds(6))
          if !Task.isCancelled { deletions?.settle(deletion) }
        }
      }
    }
    .subscribing(WatchCourses(), into: $courses)
  }

  private var books: [CourseBook] {
    (courses?.value ?? []).compactMap { entry in
      if case .course(let summary) = entry { CourseBook(summary) } else { nil }
    }
  }

  private func start(_ topic: String) {
    run { () async throws(HostError) in
      let course = try await host.run(StartCourse(topic: topic))
      wish = ""
      started = course.id
      origin = .wish
      withAnimation(Motion.expand) { building = course.id }
    }
  }

  /// A book read before opens to read; one still being built opens its builder, growing out of the book.
  private func choose(_ book: CourseBook) {
    guard let summary = summary(of: book.id) else { return }
    if summary.readCount > 0 {
      openPlace(.courses(book.id))
    } else {
      started = nil
      origin = .book(book.id)
      withAnimation(Motion.expand) { building = book.id }
    }
  }

  private func collapse(_ course: EntityID) {
    origin = .book(course)
    withAnimation(Motion.expand) { building = nil }
    bumped = Bump(book: course, serial: (bumped?.serial ?? 0) + 1)
  }

  private func read(_ course: EntityID, from lesson: Lesson.ID?) {
    run { () async throws(HostError) in
      if let lesson { _ = try await host.run(OpenLesson(course: course, lesson: lesson)) }
      building = nil
      openPlace(.courses(course))
    }
  }

  private func delete(_ book: CourseBook) {
    run { () async throws(HostError) in
      _ = try await host.run(DeleteCourse(book.id))
      if building == book.id { building = nil }
      deletions?.happened(1, undoManager: undoManager) {
        run { () async throws(HostError) in _ = try await host.run(RestoreDeletedCourse()) }
      }
    }
  }

  private func summary(of course: EntityID) -> CourseSummary? {
    for entry in courses?.value ?? [] {
      if case .course(let summary) = entry, summary.id == course { return summary }
    }
    return nil
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
