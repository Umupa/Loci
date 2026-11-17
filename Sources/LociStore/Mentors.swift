import Foundation
import LociModel

extension Store {
  static let catalogFile = "catalog.yaml"
  static let lessonsFolder = "lessons"

  public func mentor(_ id: EntityID) throws -> Mentor {
    try decodeJSON(Mentor.self, at: mentorFolder(id).appending(path: Self.mentorFile))
  }

  /// A mentor without a `catalog.yaml` has an empty catalog.
  public func catalog(of mentor: EntityID) throws -> Catalog {
    let url = try mentorFolder(mentor).appending(path: Self.catalogFile)
    do {
      return try decodeYAML(Catalog.self, at: url)
    } catch StoreError.notFound {
      return try Catalog(chapters: [])
    }
  }

  /// Throws `notFound` for a lesson that is in the catalog but not written yet.
  public func lesson(_ ref: LessonRef) throws -> LessonText {
    let url = try lessonFile(ref)
    do {
      return try LessonText(parsing: try readText(url))
    } catch let error as StoreError {
      throw error
    } catch {
      throw StoreError.invalid(problem(at: url, error))
    }
  }

  /// Makes the mentor's folder with its `mentor.json`, an empty catalog and an empty `lessons` folder.
  public func create(_ mentor: Mentor) throws {
    guard !folderExists(holding: mentor.id, in: mentorsFolder, file: Self.mentorFile) else {
      throw StoreError.alreadyExists(mentor.id)
    }
    let folder = mentorsFolder.appending(path: FolderName.make(for: mentor.name, id: mentor.id))
    try FileManager.default.createDirectory(
      at: folder.appending(path: Self.lessonsFolder), withIntermediateDirectories: true)
    try write(Data(Formats.yaml(Catalog(chapters: [])).utf8), to: folder.appending(path: Self.catalogFile))
    try write(Formats.document(mentor), to: folder.appending(path: Self.mentorFile))
  }

  /// Rewrites `mentor.json`. The folder keeps its name: an agent may be working inside it.
  public func save(_ mentor: Mentor) throws {
    try write(Formats.document(mentor), to: mentorFolder(mentor.id).appending(path: Self.mentorFile))
  }

  public func save(_ catalog: Catalog, of mentor: EntityID) throws {
    try write(Data(Formats.yaml(catalog).utf8), to: mentorFolder(mentor).appending(path: Self.catalogFile))
  }

  public func save(_ lesson: LessonText, as ref: LessonRef) throws {
    try write(Data(lesson.text().utf8), to: lessonFile(ref))
  }

  public func deleteMentor(_ id: EntityID, notes: NotesOnDelete) throws {
    try discard(mentorFolder(id))
    if notes == .delete {
      try discard(notesFolder.appending(path: Self.mentorNotesFolder).appending(path: id.description))
    }
  }

  private func lessonFile(_ ref: LessonRef) throws -> URL {
    try mentorFolder(ref.mentor).appending(path: Self.lessonsFolder).appending(path: "\(ref.lesson).md")
  }
}
