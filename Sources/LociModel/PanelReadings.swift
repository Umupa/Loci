import Foundation

/// The snapshots of the sources a panel column's rows point at, by source. What turns a row's fields into
/// numbers on screen, here and on another Mac alike.
public struct PanelReadings: Hashable, Codable, Sendable {
  public let snapshots: [SourceKey: SourceSnapshot]

  public init(_ snapshots: [SourceKey: SourceSnapshot] = [:]) {
    self.snapshots = snapshots
  }

  public func value(_ field: SourceField, of home: Home) -> SourceValue? {
    snapshots[SourceKey(home, field.source)]?.value(field)
  }

  /// `nil` when the source has not been fetched yet or has no such number.
  public func number(_ number: PanelNumber, of home: Home) -> Double? {
    switch number {
    case .fixed(let value): value
    case .field(let field): value(field, of: home)?.number
    }
  }

  /// A number field is written as it is, so a date given as `20261123` still shows.
  public func text(_ text: PanelText, of home: Home) -> String? {
    switch text {
    case .fixed(let words): return words
    case .field(let field):
      switch value(field, of: home) {
      case .text(let words): return words
      case .number(let number): return number.formatted(.number.grouping(.never))
      case .points, .candles, nil: return nil
      }
    }
  }

  /// When the panel's numbers were got: the oldest of its sources, stale when any of them is.
  public func time(of panel: Panel, in home: Home) -> PanelDataTime? {
    let found = panel.sources(of: home).compactMap { snapshots[$0] }
    guard let oldest = found.map(\.fetched).min() else { return nil }
    return PanelDataTime(fetched: oldest, stale: found.contains(where: \.isStale))
  }
}

/// The time written right of a panel's title, and whether a source behind it failed its last try.
public struct PanelDataTime: Hashable, Sendable {
  public let fetched: Timestamp
  public let stale: Bool

  public init(fetched: Timestamp, stale: Bool) {
    self.fetched = fetched
    self.stale = stale
  }
}

extension Panel {
  /// Every source the panel's rows point at.
  public func sources(of home: Home) -> Set<SourceKey> {
    Set(fields.map { SourceKey(home, $0.source) })
  }

  /// Every field the panel's rows point at.
  public var fields: [SourceField] {
    let rows =
      switch body {
      case .rows(let rows): rows
      case .pages(let pages): pages.flatMap(\.rows)
      }
    return rows.flatMap(\.fields)
  }
}

extension PanelRow {
  var fields: [SourceField] {
    switch self {
    case .quotes(let quotes):
      return quotes.flatMap { quote in
        [quote.price.field, quote.change?.field, quote.spark, quote.asOf?.field].compactMap { $0 }
      }
    case .line(let chart):
      return [chart.value.field, chart.change?.field].compactMap { $0 }
        + chart.ranges.values.sorted { "\($0)" < "\($1)" }
    case .ruler(let ruler):
      return [ruler.value, ruler.share, ruler.low, ruler.high].compactMap(\.field)
    case .allocation(let allocation):
      return [allocation.total?.field, allocation.change?.field].compactMap { $0 }
        + allocation.slices.flatMap { [$0.actual.field, $0.target?.field].compactMap { $0 } }
    case .heat(let tiles):
      return tiles.flatMap { [$0.weight.field, $0.change.field].compactMap { $0 } }
    case .candles(let candles):
      return [candles.series] + candles.lines.compactMap(\.price.field)
    case .zones(let zones):
      return zones.rows.compactMap(\.value.field)
    case .sentence, .cells, .label, .list, .prominent, .bars, .picture, .items:
      return []
    }
  }
}

extension PanelText {
  public var field: SourceField? {
    if case .field(let field) = self { field } else { nil }
  }
}
