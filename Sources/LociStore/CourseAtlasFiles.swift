import Foundation
import LociModel

extension Store {
  static let atlasFile = "atlas.json"

  /// The course's atlas, or nil before the companion has drawn one.
  public func courseAtlas(_ id: EntityID) throws -> CourseAtlas? {
    let file = courseFolder(id).appending(path: Self.atlasFile, directoryHint: .notDirectory)
    do {
      let bytes = try inCourseDirectory(id) { try $0.read(Self.atlasFile) }
      return try JSONDecoder().decode(CourseAtlas.self, from: bytes)
    } catch StoreError.notFound {
      return nil
    } catch {
      throw StoreError.invalid(problem(at: file, error).attributed(to: .course(id)))
    }
  }

  /// Replaces the course's atlas; every lesson it points at must be in the course's plan.
  public func writeCourseAtlas(_ atlas: CourseAtlas, in id: EntityID) throws {
    let course = try course(id)
    do {
      try atlas.check(against: course.lessons)
    } catch let error as ModelError {
      throw StoreError.invalid(
        FileProblem(
          path: relativePath(of: courseFolder(id).appending(path: Self.atlasFile)), kind: .invalid,
          reason: error.description, subject: .course(id)))
    }
    try inCourseDirectory(id) { directory in
      _ = try directory.replace(Formats.document(atlas), at: Self.atlasFile)
    }
  }
}
