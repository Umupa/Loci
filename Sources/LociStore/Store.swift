import Foundation
import LociModel

/// The Loci folder: mentors, the library and notes, kept as files that people and agents can read and write.
///
/// A store knows only where the folder is and how to discard things. Every call goes to the disk, so it
/// always sees what an agent wrote last, and copies of a store never disagree.
public struct Store: Sendable {
  public let root: URL
  let discard: Discard

  public init(root: URL, discard: Discard) {
    self.root = root
    self.discard = discard
  }

  var mentorsFolder: URL { root.appending(path: "mentors", directoryHint: .isDirectory) }
  var libraryFolder: URL { root.appending(path: "library", directoryHint: .isDirectory) }
  var notesFolder: URL { root.appending(path: "notes", directoryHint: .isDirectory) }

  func relativePath(of url: URL) -> String {
    let base = root.standardizedFileURL.path(percentEncoded: false)
    let path = url.standardizedFileURL.path(percentEncoded: false)
    let prefix = base.hasSuffix("/") ? base : base + "/"
    let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    return relative.hasSuffix("/") ? String(relative.dropLast()) : relative
  }
}

/// How a store gets rid of a deleted mentor, item or notes file.
public struct Discard: Sendable {
  let remove: @Sendable (URL) throws -> Void

  public init(_ remove: @escaping @Sendable (URL) throws -> Void) {
    self.remove = remove
  }

  /// Moves it to the user's Trash, where it can be restored from the Finder.
  public static let toTrash = Discard { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

  /// Removes it for good.
  public static let permanently = Discard { try FileManager.default.removeItem(at: $0) }
}

/// What a caller decides about the notes on content it deletes.
public enum NotesOnDelete: Sendable {
  case keep
  case delete
}
