import LociModel

/// Which sentence is playing, and whether the transcript scrolls along with it.
///
/// The transcript follows the sound until the reader scrolls it by hand; then it stays where they put it,
/// and «back to playing» brings the sentence playing into view and starts following again.
struct TranscriptFollow: Equatable {
  private(set) var following = true

  /// The last sentence that has started by `time`; a pause between two sentences keeps the earlier one.
  static func playing(in segments: [Transcript.Segment], at time: Duration) -> Int? {
    var low = 0
    var high = segments.count
    while low < high {
      let middle = (low + high) / 2
      if segments[middle].start <= time { low = middle + 1 } else { high = middle }
    }
    return low == 0 ? nil : low - 1
  }

  /// The reader scrolled the transcript themselves.
  mutating func scrolledByHand() {
    following = false
  }

  /// «Back to playing», or a sentence chosen to play from.
  mutating func resume() {
    following = true
  }
}
