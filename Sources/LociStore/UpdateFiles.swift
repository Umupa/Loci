import Foundation
import LociModel

/// A copy of Loci downloaded, checked and waiting to be put in place, with the release it came from.
public struct StagedUpdate: Sendable {
  public let release: AppRelease
  public let app: URL
}

/// Where updating one copy of Loci keeps its files: downloads on their way in, what it unpacks and patches,
/// staged copies, the copy an update replaced and the record of a release that did not start. Each bundle identifier has its own folder
/// under `updates/`, so a test copy and the published one never see each other's.
public struct UpdateFiles: Sendable {
  public let support: Support
  /// The bundle identifier of the copy running.
  public let identifier: String
  /// The name of the app bundle a release holds.
  public let appName: String

  public init(support: Support, identifier: String, appName: String) {
    self.support = support
    self.identifier = identifier
    self.appName = appName
  }

  var updates: URL { support.root.appending(path: "updates", directoryHint: .isDirectory) }

  public var folder: URL { updates.appending(path: identifier, directoryHint: .isDirectory) }

  private func versionFolder(_ version: ReleaseVersion) -> URL {
    folder.appending(path: version.description, directoryHint: .isDirectory)
  }

  /// A new empty folder for unpacking or patching, inside this copy's folder; removed with `support.discard`.
  public func scratchFolder() throws -> URL {
    let scratch = folder.appending(path: "scratch/\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    return scratch
  }

  /// Where a download with this checksum collects, so an interrupted download carries on.
  public func partialDownload(checksum: String) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appending(path: "\(checksum).partial")
  }

  /// An empty folder for `release`'s copy of the app, replacing whatever an earlier try left there.
  public func stagingFolder(for release: AppRelease) throws -> URL {
    let staging = versionFolder(release.version)
    try? FileManager.default.removeItem(at: staging)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    return staging
  }

  /// Records that the app in `release`'s staging folder is complete and checked.
  public func markStaged(_ release: AppRelease) throws -> StagedUpdate {
    let staging = versionFolder(release.version)
    try JSONEncoder().encode(release).write(to: staging.appending(path: "release.json"))
    return StagedUpdate(release: release, app: staging.appending(path: appName, directoryHint: .isDirectory))
  }

  /// Every staged copy whose staging finished, newest first.
  public func stagedUpdates() -> [StagedUpdate] {
    Self.staged(in: folder, appName: appName)
  }

  /// Removes a staged copy and the folder it waited in.
  public func discardStaged(_ staged: StagedUpdate) {
    try? FileManager.default.removeItem(at: staged.app.deletingLastPathComponent())
  }

  /// Removes what releases up to 1.8.8 left directly in `updates/`: a download that never finished and a copy
  /// staged but never put in place, each up to a few hundred MB. Only the published copy, which wrote them,
  /// should call this.
  public func removeEarlierLayout() {
    let entries = (try? FileManager.default.contentsOfDirectory(at: updates, includingPropertiesForKeys: nil)) ?? []
    for entry in entries
    where entry.pathExtension == "partial" || ReleaseVersion(entry.lastPathComponent) != nil {
      try? FileManager.default.removeItem(at: entry)
    }
  }

  private static func staged(in folder: URL, appName: String) -> [StagedUpdate] {
    let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    return folders.compactMap { folder in
      guard ReleaseVersion(folder.lastPathComponent) != nil,
        let data = try? Data(contentsOf: folder.appending(path: "release.json")),
        let release = try? JSONDecoder().decode(AppRelease.self, from: data)
      else { return nil }
      return StagedUpdate(release: release, app: folder.appending(path: appName, directoryHint: .isDirectory))
    }
    .sorted { $0.release.version > $1.release.version }
  }
}

extension Support {
  /// How many bytes `file` holds; 0 when there is none.
  public func size(of file: URL) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
  }
}
