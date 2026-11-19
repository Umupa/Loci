import Foundation

/// A published copy of Loci newer than the one running.
public struct AppRelease: Hashable, Sendable {
  public let version: ReleaseVersion
  /// The disk image to download.
  public let package: URL

  public init(version: ReleaseVersion, package: URL) {
    self.version = version
    self.package = package
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
  /// The state now, then again whenever it changes.
  func states() -> AsyncStream<AppUpdate>
  /// Downloads and checks an available or failed release. Returns when it is ready or has failed.
  func download() async
  /// Puts a ready release in place of this copy and arranges for it to open once this one quits. Returns
  /// whether Loci should quit now; on failure the state says why.
  func install() async -> Bool
}

/// Nothing to update: previews, snapshots, and builds that do not know their own version.
public struct NoUpdates: Updates {
  public init() {}

  public func states() -> AsyncStream<AppUpdate> {
    AsyncStream { $0.yield(.current) }
  }

  public func download() async {}

  public func install() async -> Bool { false }
}
