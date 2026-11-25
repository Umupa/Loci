import Foundation

/// What a line or a candle chart draws: a field's points over a span, or its candles.
public enum SourceHistory: Hashable, Codable, Sendable {
  case points([SourcePoint])
  case candles([SourceCandle])

  /// The most points a line is drawn with; a panel is never wider than this many.
  public static let mostPoints = 300
  /// The most candles a chart shows, the newest.
  public static let mostCandles = 60

  /// The points within `range` of the newest, thinned evenly to at most `most`, keeping the first and last.
  public static func cut(_ points: [SourcePoint], to range: PanelRange, most: Int = mostPoints) -> [SourcePoint] {
    let sorted = points.sorted { $0.at < $1.at }
    guard let newest = sorted.last else { return [] }
    let start = newest.at.millisecondsSince1970 - range.milliseconds
    return thinned(sorted.filter { $0.at.millisecondsSince1970 >= start }, to: most)
  }

  /// Evenly spaced picks that keep the first and the last.
  public static func thinned<Element>(_ elements: [Element], to most: Int) -> [Element] {
    guard elements.count > most, most >= 2 else { return elements }
    let step = Double(elements.count - 1) / Double(most - 1)
    return (0..<most).map { elements[Int((Double($0) * step).rounded())] }
  }
}
