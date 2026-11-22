import Foundation
import LociModel

/// Reads current covers, using folder names as hints and the item files as authority.
public actor CoverReader {
  private let store: Store
  private var folders: [EntityID: URL]?

  public init(_ store: Store) {
    self.store = store
  }

  public func cover(of item: EntityID) throws -> Data? {
    if folders == nil {
      folders = Dictionary(
        store.subfolders(of: store.libraryFolder).compactMap { folder in
          FolderName.id(in: folder.lastPathComponent).map { ($0, folder) }
        }, uniquingKeysWith: { first, _ in first })
    }
    if let hint = folders?[item], store.id(ofFolder: hint) == item {
      return try store.cover(in: hint)
    }
    folders?[item] = nil
    let folder = try store.itemFolder(item)
    folders?[item] = folder
    return try store.cover(in: folder)
  }
}
