import Foundation
import LociModel

/// Turns changed paths into `ContentChange`s.
///
/// It remembers which id each folder held, so a folder that was deleted or renamed away can still be
/// named. This memory belongs to one watcher; nothing else reads or changes it.
struct ChangeMap {
  private var folders: [String: EntityID]

  init(folders: [String: EntityID]) {
    self.folders = folders
  }

  /// `identify` reads the id written in a folder (`library/<name>`), or returns `nil` when it cannot.
  mutating func changes(at relativePaths: [String], identify: (String) -> EntityID?) -> Set<ContentChange> {
    Set(relativePaths.compactMap { change(at: $0, identify: identify) })
  }

  private mutating func change(at path: String, identify: (String) -> EntityID?) -> ContentChange? {
    let parts = path.split(separator: "/").map(String.init)
    if parts == [Store.coursesFolder] { return .everything }
    guard parts.count >= 2 else { return nil }
    let rest = Array(parts.dropFirst(2))
    switch parts[0] {
    case Store.agentFolderName:
      if parts[1] == "workspace", rest.count >= 4, rest[0] == Store.coursesFolder,
        rest.last?.hasSuffix(".md") == true, let id = EntityID(canonical: rest[1])
      {
        return .courseActivity(id)
      }
      return Self.lociFile(parts[1], rest)
    case "library":
      guard rest.isEmpty || Self.isItemFile(rest) else { return nil }
      return id(ofFolder: "library/\(parts[1])", identify: identify).map(ContentChange.item) ?? .everything
    case Store.coursesFolder:
      guard let id = EntityID(canonical: parts[1]) else { return nil }
      if rest.count == 2, rest[0] == Store.lessonNotesFolder, rest[1].hasSuffix(".jsonl"),
        let lesson = Lesson.ID(String(rest[1].dropLast(6)))
      {
        return .notes(.lesson(course: id, lesson: lesson))
      }
      if rest.isEmpty || rest == [Store.courseFile] || rest == [Store.lessonNotesFolder]
        || rest.first == Store.lessonsFolder
      {
        return .course(id)
      }
      return nil
    case "notes":
      return Self.notes(Array(parts.dropFirst())).map(ContentChange.notes)
    default:
      return nil
    }
  }

  /// The files a reader sees of an item; work in progress under `.work/` is not one of them.
  private static func isItemFile(_ rest: [String]) -> Bool {
    switch rest.count {
    case 1:
      let stem = (rest[0] as NSString).deletingPathExtension
      return [
        Store.itemFile, Store.contentFile, Store.pdfFile, Store.transcriptFile, Store.outlineFile,
        Store.keyPointsFile,
      ].contains(rest[0])
        || [Store.mediaName, Store.coverName].contains(stem)
    case 2: return rest[0] == Store.translationsFolder || rest[0] == Store.imagesFolder
    default: return false
    }
  }

  /// The files under `agent/` the person sees. Loci's workspace, the conversation copies and the
  /// generated instructions belong to nobody's view.
  private static func lociFile(_ name: String, _ rest: [String]) -> ContentChange? {
    switch (name, rest.count) {
    case (AgentFile.displayName.name, 0): .loci(.name)
    case (Store.soulFile, 0): .loci(.soul)
    case (Store.profileFile, 0): .loci(.profile)
    case (Store.memoryFile, 0): .loci(.memory)
    case (Store.dayNotesFolder, _): .loci(.notes)
    case (Store.diaryFolder, _): .loci(.diary)
    case (Store.panelsFolder, _): .loci(.panels)
    case (_, 0) where name.hasPrefix(Store.avatarName + "."): .loci(.avatar)
    default: nil
    }
  }

  private static func notes(_ parts: [String]) -> ContentRef? {
    guard let file = parts.last, file.hasSuffix(".jsonl") else { return nil }
    guard parts.count == 2, parts[0] == Store.libraryNotesFolder else { return nil }
    return EntityID(canonical: String(file.dropLast(6))).map(ContentRef.item)
  }

  private mutating func id(ofFolder folder: String, identify: (String) -> EntityID?) -> EntityID? {
    if let id = identify(folder) {
      folders[folder] = id
      return id
    }
    return folders[folder] ?? FolderName.id(in: String(folder.split(separator: "/").last ?? ""))
  }
}
