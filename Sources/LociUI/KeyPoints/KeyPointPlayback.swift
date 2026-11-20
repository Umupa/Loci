import LociModel

/// Playing only the key points: from the end of one straight to the start of the next, and stopping after
/// the last.
struct KeyPointPlayback: Equatable {
  /// In time order, apart.
  let spans: [Range<Duration>]

  init(_ points: [KeyPoint]) {
    spans = points.compactMap { point in
      guard let span = point.span, let end = span.end else { return nil }
      return span.start..<end
    }
  }

  enum Step: Equatable {
    case stay
    case jump(to: Duration)
    case stop
  }

  /// What to do with playback at `time`.
  func step(at time: Duration) -> Step {
    if spans.contains(where: { $0.contains(time) }) { return .stay }
    if let next = spans.first(where: { $0.lowerBound > time }) { return .jump(to: next.lowerBound) }
    return spans.isEmpty ? .stay : .stop
  }

  /// The key point playing at `time`, by index.
  func playing(at time: Duration) -> Int? {
    spans.firstIndex { $0.contains(time) }
  }
}
