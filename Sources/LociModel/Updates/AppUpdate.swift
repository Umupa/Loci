import Foundation

/// A published copy of Loci newer than the one running.
public struct AppRelease: Hashable, Codable, Sendable {
  public let version: ReleaseVersion
  /// The disk image, at its first place and then at each mirror, tried in this order.
  public let images: [URL]
  /// The SHA-256 of the disk image, in lowercase hexadecimal.
  public let checksum: String
  /// The app zipped whole, which a full update unpacks in place of the disk image; `nil` for a feed from
  /// before there was one.
  public let archive: ReleaseFile?
  /// Every file of the new copy with its checksum, which a patched copy must match.
  public let manifest: ReleaseFile?
  /// What turns each of a few earlier releases into this one.
  public let patches: [ReleasePatch]
  /// The changes of this release and the few before it, newest first.
  public let notes: [ReleaseNotes]

  public init(
    version: ReleaseVersion, image: URL, mirrors: [URL] = [], checksum: String, archive: ReleaseFile? = nil,
    manifest: ReleaseFile? = nil, patches: [ReleasePatch] = [], notes: [ReleaseNotes] = []
  ) {
    self.version = version
    images = [image] + mirrors
    self.checksum = checksum
    self.archive = archive
    self.manifest = manifest
    self.patches = patches
    self.notes = notes
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(ReleaseVersion.self, forKey: .version)
    images = try container.decode([URL].self, forKey: .images)
    checksum = try container.decode(String.self, forKey: .checksum)
    archive = try container.decodeIfPresent(ReleaseFile.self, forKey: .archive)
    manifest = try container.decodeIfPresent(ReleaseFile.self, forKey: .manifest)
    patches = try container.decodeIfPresent([ReleasePatch].self, forKey: .patches) ?? []
    notes = try container.decodeIfPresent([ReleaseNotes].self, forKey: .notes) ?? []
  }

  /// The patch from `running` and the manifest to check its result against, when the release has both.
  public func patch(from running: ReleaseVersion) -> (patch: ReleaseFile, manifest: ReleaseFile)? {
    guard let manifest, let patch = patches.first(where: { $0.from == running }) else { return nil }
    return (patch.file, manifest)
  }

  /// The changes of every version after `running` up to this one, newest first.
  public func changes(since running: ReleaseVersion) -> [ReleaseNotes] {
    notes.filter { $0.version > running && $0.version <= version }.sorted { $0.version > $1.version }
  }
}

/// What Loci is busy with that a restart would cut short.
public enum Busy: Hashable, Sendable {
  /// Loci is answering in a conversation.
  case answering
  /// A run in the background: refreshing a panel, looking back on a day, or a schedule or follow-up.
  case running
  /// The library is downloading, transcribing or taking in items.
  case library
}

/// Where updating this copy of Loci stands.
public enum AppUpdate: Hashable, Sendable {
  /// No newer release is known.
  case current
  /// A newer release on its way in by itself; the share is `nil` while the size is unknown.
  case downloading(AppRelease, Fraction?)
  /// Downloaded and checked. Restarting puts it in place and opens it; quitting puts it in place.
  case ready(AppRelease)
  /// Ready, asked to restart, and holding off while Loci is busy; it restarts by itself once Loci is not.
  case waiting(AppRelease, for: Busy)
  case failed(AppRelease, UpdateFailure)
  /// Running from a disk image or a place macOS moved it to, where it cannot be replaced; nothing downloads.
  case misplaced
}

/// Why an update did not go through, in the few kinds the person is told about.
public enum UpdateFailure: Hashable, Sendable {
  /// No place served the disk image, or it could not be unpacked.
  case download
  /// The disk image did not match the release's checksum.
  case checksum
  /// The new copy is not signed by the certificate this one is.
  case signature
  /// The new copy could not be put in place of this one, or opened.
  case install
  /// The new copy was put in place but quit before it started, so this one was put back.
  case launch
}

/// Updating the copy of Loci that is running on this Mac.
public protocol Updates: Sendable {
  /// Looks for a newer release and downloads it in the background. Returns once it has looked.
  func check() async throws(UpdateCheckError)
  /// The state now, then again whenever it changes.
  func states() -> AsyncStream<AppUpdate>
  /// Downloads a failed release again. Returns when it is ready or has failed.
  func retry() async
  /// Puts a ready release in place and quits so it opens, once nothing is busy; a waiting one goes at once.
  func restart() async
  /// Puts a ready release in place without opening it, as Loci quits. A failure leaves it ready for next time.
  func finishOnQuit() async
}

public enum UpdateCheckError: Error {
  case unsupported
  case unavailable
  /// Running from a disk image or a place macOS moved it to.
  case misplaced
}

/// Nothing to update: previews, snapshots, and builds that do not know their own version.
public struct NoUpdates: Updates {
  public init() {}

  public func check() async throws(UpdateCheckError) { throw .unsupported }

  public func states() -> AsyncStream<AppUpdate> {
    AsyncStream { $0.yield(.current) }
  }

  public func retry() async {}

  public func restart() async {}

  public func finishOnQuit() async {}
}
