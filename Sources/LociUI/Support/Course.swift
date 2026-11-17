import LociModel

/// A mentor's course as the sidebar shows it: its title, its lessons in reading order, and the lesson
/// choosing the course opens.
struct Course: Equatable {
  let mentor: Mentor
  let lessons: [Entry]
  /// The lesson the course opens at; `nil` until a lesson is written.
  let current: Lesson.Slug?

  /// How far the reader is with one lesson, as its glyph shows.
  enum State: Equatable {
    case read, current, unread, unwritten
  }

  struct Entry: Equatable {
    let lesson: Lesson
    let state: State
  }

  /// `open` is the lesson on screen, which is the course's current lesson while it is shown.
  init(page: MentorPage, open: Lesson.Slug? = nil) {
    let lessons = page.catalog?.chapters.flatMap(\.lessons) ?? []
    let written = Set(page.writtenLessons)
    let current =
      open.flatMap { open in lessons.contains { $0.slug == open } ? open : nil }
      ?? page.currentLesson
    mentor = page.mentor
    self.current = current
    self.lessons = lessons.map { lesson in
      let state: State =
        if lesson.slug == current { .current } else if page.readLessons.contains(lesson.slug) {
          .read
        } else if written.contains(lesson.slug) { .unread } else { .unwritten }
      return Entry(lesson: lesson, state: state)
    }
  }

  /// What the course is called: what the person asked to learn, or the mentor's name when that is unknown.
  var title: String { mentor.request ?? mentor.name }

  /// Where choosing the course goes: its current lesson, or the mentor's page while nothing is written.
  var destination: Place {
    guard let current else { return .mentor(mentor.id) }
    return .lesson(LessonRef(mentor: mentor.id, lesson: current))
  }
}
