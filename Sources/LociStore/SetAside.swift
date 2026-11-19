import Foundation
import LociModel

/// `.deleted/<id>/` under the root: items deleted a moment ago, with their notes, kept until the deletion
/// can no longer be undone. The library and its watcher do not look there.
extension Store {
  static let setAsideFolder = ".deleted"
  private static let notesName = "notes.jsonl"

  private var setAsideRoot: URL { root.appending(path: Self.setAsideFolder, directoryHint: .isDirectory) }

  /// Moves the item's folder and its notes out of the library.
  public func setAside(_ id: EntityID) throws {
    let folder = try itemFolder(id)
    let place = setAsideRoot.appending(path: id.description, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: folder, to: place.appending(path: folder.lastPathComponent))
    let notes = notesFile(on: .item(id))
    if FileManager.default.fileExists(atPath: notes.path(percentEncoded: false)) {
      try FileManager.default.moveItem(at: notes, to: place.appending(path: Self.notesName))
    }
  }

  /// The items set aside, in no particular order.
  public func setAsideItems() -> [EntityID] {
    subfolders(of: setAsideRoot).compactMap { EntityID(canonical: $0.lastPathComponent) }
  }

  /// Puts an item set aside back where it was, notes and all.
  public func restore(_ id: EntityID) throws {
    let place = setAsideRoot.appending(path: id.description, directoryHint: .isDirectory)
    let notes = place.appending(path: Self.notesName)
    if FileManager.default.fileExists(atPath: notes.path(percentEncoded: false)) {
      let back = notesFile(on: .item(id))
      try FileManager.default.createDirectory(
        at: back.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.moveItem(at: notes, to: back)
    }
    for folder in subfolders(of: place) {
      try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
      try FileManager.default.moveItem(at: folder, to: libraryFolder.appending(path: folder.lastPathComponent))
    }
    try FileManager.default.removeItem(at: place)
  }

  /// Gets rid of an item set aside for good, the way this store discards things.
  public func discardSetAside(_ id: EntityID) throws {
    let place = setAsideRoot.appending(path: id.description, directoryHint: .isDirectory)
    for folder in subfolders(of: place) { try discard(folder) }
    try discard(place)
  }

  /// Gets rid of an item still in the library at once, with its notes. Used when adding it failed half way.
  public func deleteItem(_ id: EntityID) throws {
    try discard(itemFolder(id))
    try discard(notesFile(on: .item(id)))
  }
}
