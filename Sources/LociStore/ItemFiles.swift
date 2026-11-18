import Foundation
import LociModel

/// Where an item's files are, for an agent that reads them itself.
public struct ItemFiles: Hashable, Sendable {
  public let folder: URL
  /// The file that holds what the item says: `content.md`, `content.pdf` or `transcript.json`, whichever
  /// is there first in that order; `nil` while none is.
  public let content: URL?
  /// The item's notes, one per line. It may not exist yet.
  public let notes: URL
}

extension Store {
  static let readableFiles = [contentFile, "content.pdf", "transcript.json"]

  public func itemFiles(_ item: EntityID) throws -> ItemFiles {
    let folder = try itemFolder(item)
    let content = Self.readableFiles.lazy.map { folder.appending(path: $0) }.first {
      FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
    }
    return ItemFiles(folder: folder, content: content, notes: notesFile(on: .item(item)))
  }
}
