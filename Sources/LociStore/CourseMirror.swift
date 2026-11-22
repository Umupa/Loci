import Foundation
import GRDB
import LociModel

extension StoreDatabase {
  public func coursePages() throws -> [CoursePage] {
    try queue.read { db in
      let documents = try String.fetchAll(db, sql: "SELECT document FROM course ORDER BY created_at DESC, id DESC")
      return try documents.map { document in
        let course = try JSONDecoder().decode(Course.self, from: Data(document.utf8))
        let rows = try String.fetchAll(
          db, sql: "SELECT document FROM course_lesson WHERE course_id = ? ORDER BY position",
          arguments: [course.id.description])
        let lessons = try rows.map { try JSONDecoder().decode(CourseLesson.self, from: Data($0.utf8)) }
        return CoursePage(course: course, lessons: lessons)
      }
    }
  }

  static func courseUpdate(
    _ id: EntityID, from store: Store, problems: inout [FileProblem]
  ) -> MirrorUpdate {
    do {
      let page = try store.coursePage(id)
      let notes = store.lessonNotes(in: page.course)
      problems += page.lessons.compactMap {
        if case .invalid(let problem) = $0.body { problem } else { nil }
      }
      problems += notes.values.flatMap(\.problems)
      return .course(id, page, notes: notes.mapValues(\.value))
    } catch StoreError.notFound {
      return .course(id, nil, notes: [:])
    } catch {
      let file = store.courseFolder(id).appending(path: Store.courseFile)
      problems.append(store.problem(at: file, error).attributed(to: .course(id)))
      return .course(id, nil, notes: [:])
    }
  }
}

extension MirrorUpdate {
  static func updateCourse(_ id: EntityID, page: CoursePage?, notes: [ContentRef: [Note]], in db: Database) throws {
    try db.execute(sql: "DELETE FROM course_lesson WHERE course_id = ?", arguments: [id.description])
    try db.execute(sql: "DELETE FROM course WHERE id = ?", arguments: [id.description])
    let prefix = "courses/\(id)/%"
    let oldContent = try String.fetchAll(
      db, sql: "SELECT DISTINCT content FROM note WHERE content LIKE ?",
      arguments: [prefix])
    for key in oldContent {
      guard let content = ContentKey.content(key), notes[content] == nil else { continue }
      try MirrorUpdate.notes(content, []).write(db)
    }
    guard let page else { return }
    try db.execute(
      sql: "INSERT INTO course (id, created_at, document) VALUES (?, ?, ?)",
      arguments: [id.description, page.course.createdAt.description, try json(page.course)])
    for (position, lesson) in page.lessons.enumerated() {
      try db.execute(
        sql: "INSERT INTO course_lesson (course_id, id, position, document) VALUES (?, ?, ?, ?)",
        arguments: [id.description, lesson.id.description, position, try json(lesson)])
    }
    for (content, highlights) in notes { try MirrorUpdate.notes(content, highlights).write(db) }
  }
}
