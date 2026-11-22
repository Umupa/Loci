import Foundation
import LociModel

extension Store {
  static let coursesFolder = "courses"
  static let courseFile = "course.json"
  static let lessonsFolder = "lessons"
  static let lessonNotesFolder = "notes"

  var coursesRoot: URL { root.appending(path: Self.coursesFolder, directoryHint: .isDirectory) }

  func courseFolder(_ id: EntityID) -> URL {
    coursesRoot.appending(path: id.description, directoryHint: .isDirectory)
  }

  func lessonFile(in id: EntityID, lesson: Lesson.ID) -> URL {
    courseFolder(id).appending(path: Self.lessonsFolder, directoryHint: .isDirectory)
      .appending(path: "\(lesson).md", directoryHint: .notDirectory)
  }

  private func courseFile(_ id: EntityID) -> URL {
    courseFolder(id).appending(path: Self.courseFile, directoryHint: .notDirectory)
  }

  public func courseIDs() -> [EntityID] {
    let root = coursesRoot
    var details = stat()
    guard lstat(root.path(percentEncoded: false), &details) == 0,
      details.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    else { return [] }
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles)) ?? []
    return entries.compactMap { file in
      guard let properties = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
        properties.isDirectory == true || properties.isSymbolicLink == true
      else { return nil }
      return EntityID(canonical: file.lastPathComponent)
    }.sorted()
  }

  public func course(_ id: EntityID) throws -> Course {
    try courseVersion(id).course
  }

  private func courseVersion(_ id: EntityID) throws -> (course: Course, bytes: Data) {
    let file = courseFile(id)
    do {
      return try inCourseDirectory(id) { directory in
        do {
          let bytes = try directory.read(Self.courseFile)
          return (try decodeCourse(bytes, id: id, file: file), bytes)
        } catch StoreError.notFound {
          throw StoreError.invalid(
            FileProblem(
              path: relativePath(of: file), kind: .invalid, reason: "course.json is missing",
              subject: .course(id)))
        }
      }
    } catch StoreError.notFound(let file) {
      throw StoreError.notFound(file)
    } catch {
      let issue = problem(at: file, error)
      throw StoreError.invalid(
        FileProblem(path: relativePath(of: file), kind: issue.kind, reason: issue.reason, subject: .course(id)))
    }
  }

  func decodeCourse(_ bytes: Data, id: EntityID, file: URL) throws -> Course {
    let course = try JSONDecoder().decode(Course.self, from: bytes)
    guard course.id == id else {
      throw StoreError.invalid(
        FileProblem(path: relativePath(of: file), kind: .invalid, reason: "course ID does not match its folder"))
    }
    return course
  }

  public func createCourse(_ course: Course) throws {
    guard !FileManager.default.fileExists(atPath: courseFolder(course.id).path()) else {
      throw StoreError.alreadyExists(course.id)
    }
    try inCourseDirectory(course.id, create: true) { directory in
      _ = try directory.replace(Formats.document(course), at: Self.courseFile)
    }
  }

  /// Reapplies the change to a fresh document if a coordinated editor saves while the change is prepared.
  public func editCourse<Value>(_ id: EntityID, _ change: (inout Course) throws -> Value) throws -> Value {
    let file = courseFile(id)
    for _ in 0..<8 {
      let version = try courseVersion(id)
      var next = version.course
      let result = try change(&next)
      if next == version.course {
        if try courseVersion(id).bytes == version.bytes { return result }
        continue
      }
      let bytes = try Formats.document(next)
      var coordinationError: NSError?
      var replaced: Result<Bool, any Error>?
      NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { _ in
        replaced = Result {
          try inCourseDirectory(id) { directory in
            try directory.replace(bytes, at: Self.courseFile, ifUnchanged: version.bytes)
          }
        }
      }
      if let coordinationError { throw coordinationError }
      guard let replaced else { throw CocoaError(.fileWriteUnknown) }
      if try replaced.get() { return result }
    }
    throw StoreError.invalid(
      FileProblem(
        path: relativePath(of: file), kind: .invalid, reason: "the course kept changing while it was saved",
        subject: .course(id)))
  }

  public func coursePage(_ id: EntityID) throws -> CoursePage {
    let course = try course(id)
    let lessons = course.lessons.map { lesson in
      let state: CourseLesson.Body
      do {
        state = try currentLessonText(in: id, lesson: lesson.id) == nil ? .unwritten : .written
      } catch {
        state = .invalid(problem(at: lessonFile(in: id, lesson: lesson.id), error).attributed(to: .course(id)))
      }
      return CourseLesson(
        lesson: lesson, body: state, isRead: state == .written && course.readLessons.contains(lesson.id))
    }
    return CoursePage(course: course, lessons: lessons)
  }

  public func lessonText(in id: EntityID, lesson: Lesson.ID) throws -> String? {
    let course = try course(id)
    guard course.lessons.contains(where: { $0.id == lesson }) else { throw StoreError.notFound(lesson.description) }
    return try currentLessonText(in: id, lesson: lesson)
  }

  public func writeLesson(_ markdown: String, in id: EntityID, lesson: Lesson.ID) throws {
    let course = try course(id)
    guard course.lessons.contains(where: { $0.id == lesson }) else { throw StoreError.notFound(lesson.description) }
    let file = lessonFile(in: id, lesson: lesson)
    guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw StoreError.invalid(
        FileProblem(
          path: relativePath(of: file), kind: .invalid, reason: "write some Markdown before saving the lesson",
          subject: .course(id)))
    }
    try inCourseDirectory(id) { directory in
      try directory.directory(Self.lessonsFolder, create: true) {
        _ = try $0.replace(Data(markdown.utf8), at: "\(lesson).md")
      }
    }
  }

  private func currentLessonText(in id: EntityID, lesson: Lesson.ID) throws -> String? {
    let file = lessonFile(in: id, lesson: lesson)
    do {
      let bytes = try inCourseDirectory(id) { directory in
        try directory.directory(Self.lessonsFolder) { try $0.read("\(lesson).md") }
      }
      guard let text = String(data: bytes, encoding: .utf8) else {
        throw StoreError.invalid(FileProblem(path: relativePath(of: file), kind: .unreadable, reason: "not UTF-8 text"))
      }
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw StoreError.invalid(FileProblem(path: relativePath(of: file), kind: .invalid, reason: "Markdown is empty"))
      }
      return text
    } catch StoreError.notFound {
      return nil
    } catch {
      throw StoreError.invalid(problem(at: file, error).attributed(to: .course(id)))
    }
  }

  func lessonNotes(in course: Course) -> [ContentRef: Loaded<[Note]>] {
    var notes: [ContentRef: Loaded<[Note]>] = [:]
    for lesson in course.lessons {
      let content = ContentRef.lesson(course: course.id, lesson: lesson.id)
      let loaded = self.notes(on: content)
      if !loaded.value.isEmpty || !loaded.problems.isEmpty { notes[content] = loaded }
    }
    return notes
  }
}
