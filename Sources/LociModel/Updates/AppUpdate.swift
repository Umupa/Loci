import Foundation

/// A published copy of Loci newer than the one running.
public struct AppRelease: Hashable, Sendable {
  public let version: ReleaseVersion
  /// The disk image, at its first place and then at each mirror, tried in this order.
  public let images: [URL]
  /// The SHA-256 of the disk image, in lowercase hexadecimal.
  public let checksum: String

  public init(version: ReleaseVersion, image: URL, mirrors: [URL] = [], checksum: String) {
    self.version = version
    images = [image] + mirrors
    self.checksum = checksum
  }
}

/// Where updating this copy of Loci stands.
public enum AppUpdate: Hashable, Sendable {
  /// No newer release is known.
  case current
  case available(AppRelease)
  /// `nil` while the size is unknown.
  case downloading(AppRelease, Fraction?)
  /// Downloaded and checked; installing it quits Loci and opens the new copy.
  case ready(AppRelease)
  case failed(AppRelease, reason: String)
}

/// Updating the copy of Loci that is running on this Mac.
public protocol Updates: Sendable {
  /// Looks for a newer release and offers it unless an update is already in progress.
  func check() async throws(UpdateCheckError)
  /// The state now, then again whenever it changes.
  func states() -> AsyncStream<AppUpdate>
  /// Downloads and checks an available or failed release. Returns when it is ready or has failed.
  func download() async
  /// Puts a ready release in place of this copy and arranges for it to open once this one quits. Returns
  /// whether Loci should quit now; on failure the state says why.
  func install() async -> Bool
}

public enum UpdateCheckError: Error {
  case unsupported
  case unavailable
}

/// Nothing to update: previews, snapshots, and builds that do not know their own version.
public struct NoUpdates: Updates {
  public init() {}

  public func check() async throws(UpdateCheckError) { throw .unsupported }

  public func states() -> AsyncStream<AppUpdate> {
    AsyncStream { $0.yield(.current) }
  }

  public func download() async {}

  public func install() async -> Bool { false }
}
