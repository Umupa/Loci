import Foundation
import LociModel

/// Folder names are a readable short name plus the id, such as `diao-du-019a8f3c-…`. The name only helps
/// people and agents browse; the id inside the folder's file decides what the folder holds.
enum FolderName {
  static let longestShortName = 40

  static func make(for title: String, id: EntityID) -> String {
    let short = shortName(title)
    return short.isEmpty ? id.description : "\(short)-\(id)"
  }

  static func shortName(_ title: String) -> String {
    let latin = title.applyingTransform(.toLatin, reverse: false) ?? title
    let plain = (latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin).lowercased()
    let words = plain.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
    guard let first = words.first else { return "" }
    var name = String(first.prefix(longestShortName))
    for word in words.dropFirst() {
      guard name.count + 1 + word.count <= longestShortName else { break }
      name += "-\(word)"
    }
    return name
  }

  /// The id at the end of a folder name, if the name still ends with one.
  static func id(in name: String) -> EntityID? {
    EntityID(canonical: String(name.suffix(36)))
  }
}

private struct IdentifiedFile: Decodable {
  let id: EntityID
}

extension Store {
  static let mentorFile = "mentor.json"
  static let itemFile = "item.json"

  func mentorFolder(_ id: EntityID) throws -> URL {
    try folder(holding: id, in: mentorsFolder, file: Self.mentorFile)
  }

  func itemFolder(_ id: EntityID) throws -> URL {
    try folder(holding: id, in: libraryFolder, file: Self.itemFile)
  }

  /// The id written in a mentor's or item's folder, even when the rest of the file is invalid.
  func id(ofFolder folder: URL) -> EntityID? {
    for file in [Self.mentorFile, Self.itemFile] {
      if let data = try? read(folder.appending(path: file)) {
        return (try? JSONDecoder().decode(IdentifiedFile.self, from: data))?.id
      }
    }
    return nil
  }

  func folderExists(holding id: EntityID, in parent: URL, file: String) -> Bool {
    (try? folder(holding: id, in: parent, file: file)) != nil
  }

  /// The folder whose file holds `id`. When none does, but a folder named for the id has a file that
  /// cannot be read, that file's problem is thrown rather than `notFound`: the mentor or item is still
  /// there, only broken, and whoever asked should hear why.
  private func folder(holding id: EntityID, in parent: URL, file: String) throws -> URL {
    let folders = subfolders(of: parent)
    let named = folders.filter { FolderName.id(in: $0.lastPathComponent) == id }
    let others = folders.filter { FolderName.id(in: $0.lastPathComponent) != id }
    for folder in named + others where self.id(ofFolder: folder) == id {
      return folder
    }
    for folder in named {
      _ = try decodeJSON(IdentifiedFile.self, at: folder.appending(path: file))
    }
    throw StoreError.notFound(id.description)
  }
}
