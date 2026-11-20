import LociModel
import SwiftUI

/// How key points are named and placed in words.
enum KeyPointWords {
  /// Words in the language the view is shown in, rather than the app's.
  static func string(_ resource: LocalizedStringResource, in locale: Locale) -> String {
    var resource = resource
    resource.locale = locale
    return String(localized: resource)
  }

  static func count(_ count: KeyPointCount) -> LocalizedStringResource {
    .loci("keypoints.count \(count.range.lowerBound) \(count.range.upperBound)")
  }

  /// `1:10 — 1:40 · 0:30` for a stretch of time, `¶ 7` for a passage.
  static func place(_ point: KeyPoint) -> String {
    switch point.place {
    case .time(let span):
      let end = span.end ?? span.start
      return "\(MediaTime.text(span.start)) — \(MediaTime.text(end)) · \(MediaTime.text(end - span.start))"
    case .passage(let passage):
      return "¶ \(passage.number)"
    }
  }

  /// How many there are and, for stretches of time, how long they last together.
  static func summary(_ points: [KeyPoint], in locale: Locale) -> String {
    let total = points.compactMap(\.span).reduce(Duration.zero) { $0 + (($1.end ?? $1.start) - $1.start) }
    let count = string(.loci("keypoints.passages \(points.count)"), in: locale)
    return total > .zero ? "\(count) · \(MediaTime.text(total))" : count
  }
}
