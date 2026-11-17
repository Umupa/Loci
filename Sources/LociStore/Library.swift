import Foundation
import LociModel

extension Store {
  static let contentFile = "content.md"

  public func item(_ id: EntityID) throws -> Item {
    try decodeJSON(Item.self, at: itemFolder(id).appending(path: Self.itemFile))
  }

  /// The text of an article, as stored in `content.md`.
  public func content(of item: EntityID) throws -> String {
    try content(inFolder: itemFolder(item))
  }

  func content(inFolder folder: URL) throws -> String {
    try readText(folder.appending(path: Self.contentFile))
  }

  /// Makes the item's folder with its `item.json` and `content.md`.
  public func add(_ item: Item, content: String) throws {
    guard !folderExists(holding: item.id, in: libraryFolder, file: Self.itemFile) else {
      throw StoreError.alreadyExists(item.id)
    }
    let folder = libraryFolder.appending(path: FolderName.make(for: item.title, id: item.id))
    try write(Data(content.utf8), to: folder.appending(path: Self.contentFile))
    try write(Formats.document(item), to: folder.appending(path: Self.itemFile))
  }

  /// Rewrites `item.json`. The folder keeps its name.
  public func save(_ item: Item) throws {
    try write(Formats.document(item), to: itemFolder(item.id).appending(path: Self.itemFile))
  }

  public func deleteItem(_ id: EntityID, notes: NotesOnDelete) throws {
    try discard(itemFolder(id))
    if notes == .delete {
      try discard(notesFile(on: .item(id)))
    }
  }
}
