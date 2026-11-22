import Foundation
import LociModel

extension Store {
  public func courseDraftPath(_ course: EntityID, turn: EntityID, lesson: Lesson.ID) -> String {
    "workspace/courses/\(course)/\(turn)/\(lesson).md"
  }

  public func courseAtlasDraftPath(_ course: EntityID, turn: EntityID) -> String {
    "workspace/courses/\(course)/\(turn)/atlas.json"
  }

  public func courseDraft(_ course: EntityID, turn: EntityID, lesson: Lesson.ID) -> String? {
    let path = courseDraftPath(course, turn: turn, lesson: lesson)
    guard let text = try? readText(agentFolder.appending(path: path)), !text.isEmpty else { return nil }
    return text
  }

  public func removeCourseDrafts(_ course: EntityID, turn: EntityID) throws {
    let path = "workspace/courses/\(course)/\(turn)"
    let folder = agentFolder.appending(path: path, directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: folder.path()) else { return }
    try FileManager.default.removeItem(at: folder)
  }
}
