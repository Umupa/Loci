import Foundation
import LociModel

/// Whether the copy running can be replaced by an update.
public enum AppPlacement: Sendable, Equatable {
  case replaceable
  /// On a disk image or another volume that cannot be written.
  case diskImage
  /// Moved by macOS to a random read-only place because it was opened where it was downloaded.
  case translocated

  /// Where the app at `bundle` runs from.
  public static func of(_ bundle: URL) -> AppPlacement {
    if bundle.path(percentEncoded: false).contains("/AppTranslocation/") { return .translocated }
    if (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true { return .diskImage }
    return .replaceable
  }
}

extension UpdateFiles {
  public var previousCopy: PreviousCopy {
    let previous = folder.appending(path: "previous", directoryHint: .isDirectory)
    return PreviousCopy(
      folder: previous, app: previous.appending(path: appName, directoryHint: .isDirectory),
      release: previous.appending(path: "release.json"), started: previous.appending(path: "started"),
      failed: folder.appending(path: "failed", directoryHint: .isDirectory),
      record: folder.appending(path: "rolled-back.json"))
  }

  /// Keeps a copy of `installed` before `release` replaces it, a clone on APFS.
  public func keepPrevious(_ installed: URL, replacedBy release: AppRelease) throws -> PreviousCopy {
    let previous = previousCopy
    try? FileManager.default.removeItem(at: previous.folder)
    try FileManager.default.createDirectory(at: previous.folder, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: installed, to: previous.app)
    try JSONEncoder().encode(release).write(to: previous.release)
    return previous
  }

  /// Marks that `version` has started, when it is the release that replaced the previous copy.
  public func markStarted(_ version: ReleaseVersion) {
    let previous = previousCopy
    guard let data = try? Data(contentsOf: previous.release),
      let release = try? JSONDecoder().decode(AppRelease.self, from: data), release.version == version
    else { return }
    try? Data().write(to: previous.started)
  }

  /// Removes the previous copy once the release that replaced it has started, and a copy that did not start.
  public func forgetPrevious() {
    let previous = previousCopy
    try? FileManager.default.removeItem(at: previous.failed)
    if FileManager.default.fileExists(atPath: previous.started.path(percentEncoded: false)) {
      try? FileManager.default.removeItem(at: previous.folder)
    }
  }

  /// The release that was put back because it did not start.
  public func rolledBack() -> AppRelease? {
    guard let data = try? Data(contentsOf: previousCopy.record) else { return nil }
    return try? JSONDecoder().decode(AppRelease.self, from: data)
  }

  public func forgetRolledBack() {
    try? FileManager.default.removeItem(at: previousCopy.record)
  }
}
