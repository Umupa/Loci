import Foundation
import LociModel

/// What changed on disk. A change says only what to read again, never the new contents, so hearing
/// about the same change twice does no harm.
public enum StoreChange: Hashable, Sendable {
  /// `mentor.json`, or the whole folder appeared or went away.
  case mentor(EntityID)
  case catalog(EntityID)
  /// A lesson file was written, changed or removed.
  case lesson(LessonRef)
  /// `item.json` or `content.md`, or the whole folder.
  case item(EntityID)
  case notes(ContentRef)
  /// Events were lost or a change could not be placed; read everything again with `load()`.
  case everything
}

/// Turns changed paths into `StoreChange`s.
///
/// It remembers which id each folder held, so a folder that was deleted or renamed away can still be
/// named. This memory belongs to one watcher; nothing else reads or changes it.
struct ChangeMap {
  private var folders: [String: EntityID]

  init(folders: [String: EntityID]) {
    self.folders = folders
  }

  /// `identify` reads the id written in a folder (`mentors/<name>`), or returns `nil` when it cannot.
  mutating func changes(at relativePaths: [String], identify: (String) -> EntityID?) -> Set<StoreChange> {
    Set(relativePaths.compactMap { change(at: $0, identify: identify) })
  }

  private mutating func change(at path: String, identify: (String) -> EntityID?) -> StoreChange? {
    let parts = path.split(separator: "/").map(String.init)
    guard parts.count >= 2 else { return nil }
    let rest = Array(parts.dropFirst(2))
    switch parts[0] {
    case "mentors":
      guard let kind = Self.mentorFile(rest) else { return nil }
      guard let mentor = id(ofFolder: "mentors/\(parts[1])", identify: identify) else { return .everything }
      switch kind {
      case .mentor: return .mentor(mentor)
      case .catalog: return .catalog(mentor)
      case .lesson(let slug): return .lesson(LessonRef(mentor: mentor, lesson: slug))
      }
    case "library":
      guard rest.isEmpty || rest == [Store.itemFile] || rest == [Store.contentFile] else { return nil }
      return id(ofFolder: "library/\(parts[1])", identify: identify).map(StoreChange.item) ?? .everything
    case "notes":
      return Self.notes(Array(parts.dropFirst())).map(StoreChange.notes)
    default:
      return nil
    }
  }

  private enum MentorFile {
    case mentor
    case catalog
    case lesson(Lesson.Slug)
  }

  private static func mentorFile(_ rest: [String]) -> MentorFile? {
    switch rest.count {
    case 0: return .mentor
    case 1 where rest[0] == Store.mentorFile: return .mentor
    case 1 where rest[0] == Store.catalogFile: return .catalog
    case 2 where rest[0] == Store.lessonsFolder && rest[1].hasSuffix(".md"):
      return Lesson.Slug(String(rest[1].dropLast(3))).map(MentorFile.lesson)
    default: return nil
    }
  }

  private static func notes(_ parts: [String]) -> ContentRef? {
    guard let file = parts.last, file.hasSuffix(".jsonl") else { return nil }
    let name = String(file.dropLast(6))
    switch parts.count {
    case 2 where parts[0] == Store.libraryNotesFolder:
      return EntityID(canonical: name).map(ContentRef.item)
    case 3 where parts[0] == Store.mentorNotesFolder:
      guard let mentor = EntityID(canonical: parts[1]), let slug = Lesson.Slug(name) else { return nil }
      return .lesson(LessonRef(mentor: mentor, lesson: slug))
    default:
      return nil
    }
  }

  private mutating func id(ofFolder folder: String, identify: (String) -> EntityID?) -> EntityID? {
    if let id = identify(folder) {
      folders[folder] = id
      return id
    }
    return folders[folder] ?? FolderName.id(in: String(folder.split(separator: "/").last ?? ""))
  }
}
