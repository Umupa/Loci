import Foundation

/// A published copy of Loci newer than the one running.
public struct AppRelease: Hashable, Codable, Sendable {
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
