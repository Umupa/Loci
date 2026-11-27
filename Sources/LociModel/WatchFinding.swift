import Foundation

/// What watch triage raised for the companion to judge: one event in the world, under a key that stays the same
/// however many outlets or headlines report it, with the entries that showed it.
public struct WatchFinding: Hashable, Codable, Sendable {
  /// An entry that showed it, as its source gave it.
  public struct Evidence: Hashable, Codable, Sendable {
    public let title: String
    /// The title of the source it came from.
    public let source: String
    /// When it was first published, or fetched when the source gives no time.
    public let at: Timestamp
    public let link: URL?

    public init(title: String, source: String, at: Timestamp, link: URL? = nil) {
      self.title = title
      self.source = source
      self.at = at
      self.link = link
    }
  }

  public let key: String
  public let summary: String
  /// Why it matters to the person, as triage judged from `WATCH.md`.
  public let reason: String
  public let evidence: [Evidence]

  public init(key: String, summary: String, reason: String, evidence: [Evidence]) {
    self.key = key
    self.summary = summary
    self.reason = reason
    self.evidence = evidence
  }
}
