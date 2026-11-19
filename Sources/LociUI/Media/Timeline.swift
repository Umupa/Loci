import LociModel

/// Where things sit along a player's progress bar, as shares of its length from 0 to 1.
struct Timeline: Equatable {
  let length: Duration
  /// Where each chapter after the first begins; the bar is cut there.
  let cuts: [Double]
  /// The stretches Loci picked out, drawn in amber with a diamond at their start.
  let highlights: [ClosedRange<Double>]
  let chapters: [Outline.Chapter]

  init(length: Duration, outline: Outline?) {
    self.length = length
    let chapters = outline?.chapters ?? []
    self.chapters = chapters
    let share = { (time: Duration) in Self.share(time, of: length) }
    cuts = chapters.map(\.start).filter { $0 > .zero && $0 < length }.map(share)
    highlights = (outline?.highlights ?? []).compactMap { highlight in
      let start = share(highlight.span.start)
      let end = share(highlight.span.end ?? highlight.span.start)
      return start < 1 ? start...max(start, end) : nil
    }
  }

  func share(_ time: Duration) -> Double {
    Self.share(time, of: length)
  }

  /// The moment at a share of the bar.
  func time(at share: Double) -> Duration {
    .milliseconds(Int((min(max(share, 0), 1) * Double(length.roundedMilliseconds)).rounded()))
  }

  /// The chapter playing at `time`, if any has begun.
  func chapter(at time: Duration) -> Outline.Chapter? {
    chapters.last { $0.start <= time }
  }

  static func share(_ time: Duration, of length: Duration) -> Double {
    let total = length.roundedMilliseconds
    guard total > 0 else { return 0 }
    return min(max(Double(time.roundedMilliseconds) / Double(total), 0), 1)
  }
}

extension Duration {
  var roundedMilliseconds: Int {
    Int((Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15).rounded())
  }
}
