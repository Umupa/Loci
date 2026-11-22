import Foundation
import LociModel

extension Store {
  private var deletedCourses: URL {
    root.appending(path: Self.setAsideFolder, directoryHint: .isDirectory)
      .appending(path: Self.coursesFolder, directoryHint: .isDirectory)
  }

  private func deletedCourse(_ id: EntityID) -> URL {
    deletedCourses.appending(path: id.description, directoryHint: .isDirectory)
  }

  public func setAsideCourses() -> [EntityID] {
    subfolders(of: deletedCourses).compactMap { EntityID(canonical: $0.lastPathComponent) }
  }

  public func setAsideCourse(_ id: EntityID) throws {
    let folder = courseFolder(id)
    guard FileManager.default.fileExists(atPath: folder.path()) else {
      throw StoreError.notFound(id.description)
    }
    try FileManager.default.createDirectory(at: deletedCourses, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: folder, to: deletedCourse(id))
  }

  public func restoreCourse(_ id: EntityID) throws {
    try FileManager.default.createDirectory(at: coursesRoot, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: deletedCourse(id), to: courseFolder(id))
  }

}

extension Store {
  private var courseCleanup: URL {
    root.appending(path: Self.setAsideFolder, directoryHint: .isDirectory)
      .appending(path: "course-cleanup", directoryHint: .isDirectory)
  }

  private func cleanupRecord(_ course: EntityID) -> URL {
    courseCleanup.appending(path: course.description, directoryHint: .isDirectory)
  }

  public func expireCourseUndo(_ id: EntityID) throws {
    let record = cleanupRecord(id)
    try FileManager.default.createDirectory(at: record, withIntermediateDirectories: true)
    let contents = record.appending(path: "course", directoryHint: .isDirectory)
    try FileManager.default.moveItem(at: deletedCourse(id), to: contents)
  }

  public func coursesAwaitingCleanup() -> [EntityID] {
    subfolders(of: courseCleanup).compactMap { EntityID(canonical: $0.lastPathComponent) }
  }

  public func trashExpiredCourse(_ id: EntityID) throws -> Bool {
    let record = cleanupRecord(id)
    let contents = record.appending(path: "course", directoryHint: .isDirectory)
    let receipt = record.appending(path: "discarding", directoryHint: .notDirectory)
    if FileManager.default.fileExists(atPath: contents.path(percentEncoded: false)) {
      try write(Data(), to: receipt)
      try discard(contents)
    }
    return FileManager.default.fileExists(atPath: receipt.path(percentEncoded: false))
  }

  public func finishCourseCleanup(_ id: EntityID) throws {
    try FileManager.default.removeItem(at: cleanupRecord(id))
  }
}
