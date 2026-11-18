/// One word as it was heard, with when it was said. The text keeps the space Whisper put before it, so
/// words joined back together read as they were spoken.
public struct SpokenWord: Hashable, Sendable {
  public let text: String
  public let start: Duration
  public let end: Duration

  public init(text: String, start: Duration, end: Duration) {
    self.text = text
    self.start = start
    self.end = max(end, start)
  }
}
