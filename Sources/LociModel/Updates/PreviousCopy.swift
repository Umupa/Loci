import Foundation

/// The copy of Loci an update replaced, kept until the new copy has started, and the files the watcher that
/// puts it back reads and writes.
public struct PreviousCopy: Sendable {
  /// The folder that holds the copy, the release that replaced it, and the mark that release started.
  public let folder: URL
  /// The app as it was before the update.
  public let app: URL
  /// The release put in its place.
  public let release: URL
  /// Written once the new copy has started; the copy is no longer needed.
  public let started: URL
  /// Where the new copy goes when the previous one is put back.
  public let failed: URL
  /// The release that did not start, once the previous copy is back.
  public let record: URL

  public init(folder: URL, app: URL, release: URL, started: URL, failed: URL, record: URL) {
    self.folder = folder
    self.app = app
    self.release = release
    self.started = started
    self.failed = failed
    self.record = record
  }
}
