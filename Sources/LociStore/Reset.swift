import Foundation

extension Store {
  /// Discards the whole folder, the database in it too, and puts back an empty folder holding only
  /// `settings.json`. With `Discard.toTrash` the old folder lands in the Trash in one piece and can be put back.
  /// Nothing changes when the folder cannot be discarded.
  public func reset() throws {
    let settings = try? read(root.appending(path: Self.settingsFile))
    try discard.remove(root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    if let settings { try write(settings, to: root.appending(path: Self.settingsFile)) }
  }
}
