/// Where the reader is in one piece of content, and whether they have finished it.
///
/// It lives only in the database: losing the database loses it.
public struct ReadingState: Hashable, Codable, Sendable {
  public let position: Locator?
  public let finished: Bool
  public let updatedAt: Timestamp

  public init(position: Locator?, finished: Bool, updatedAt: Timestamp) {
    self.position = position
    self.finished = finished
    self.updatedAt = updatedAt
  }
}
