import Foundation
import LociModel

extension Support {
  /// A copy of Loci downloaded, checked and waiting to be put in place, with the release it came from.
  public struct StagedUpdate: Sendable {
    public let release: AppRelease
    public let app: URL
  }

  var updates: URL { root.appending(path: "updates", directoryHint: .isDirectory) }

  private func updateFolder(_ version: ReleaseVersion) -> URL {
    updates.appending(path: version.description, directoryHint: .isDirectory)
  }

  /// Where a release's disk image collects while it downloads, so an interrupted download carries on.
  public func partialImage(of release: AppRelease) throws -> URL {
    try FileManager.default.createDirectory(at: updates, withIntermediateDirectories: true)
    return updates.appending(path: "\(release.checksum).partial")
  }

  /// How many bytes `file` holds; 0 when there is none.
  public func size(of file: URL) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
  }

  /// An empty folder for `release`'s copy of the app, replacing whatever an earlier try left there.
  public func stagingFolder(for release: AppRelease) throws -> URL {
    let folder = updateFolder(release.version)
    try? FileManager.default.removeItem(at: folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  /// Records that the app named `appName` in `release`'s staging folder is complete and checked.
  public func markStaged(_ release: AppRelease, appName: String) throws -> StagedUpdate {
    let folder = updateFolder(release.version)
    try JSONEncoder().encode(release).write(to: folder.appending(path: "release.json"))
    return StagedUpdate(release: release, app: folder.appending(path: appName, directoryHint: .isDirectory))
  }

  /// Every staged copy named `appName` whose staging finished, newest first.
  public func stagedUpdates(appName: String) -> [StagedUpdate] {
    let folders = (try? FileManager.default.contentsOfDirectory(at: updates, includingPropertiesForKeys: nil)) ?? []
    return folders.compactMap { folder in
      guard let data = try? Data(contentsOf: folder.appending(path: "release.json")),
        let release = try? JSONDecoder().decode(AppRelease.self, from: data)
      else { return nil }
      return StagedUpdate(release: release, app: folder.appending(path: appName, directoryHint: .isDirectory))
    }
    .sorted { $0.release.version > $1.release.version }
  }

  /// Removes a staged copy and the folder it waited in.
  public func discardStaged(_ staged: StagedUpdate) {
    try? FileManager.default.removeItem(at: staged.app.deletingLastPathComponent())
  }
}
