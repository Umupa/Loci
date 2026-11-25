import Foundation

/// What `PanelCheck` asks of chart rows. A field a row points at is not looked up here: a source may be
/// saved after the panel, and until then the row shows a dash.
extension PanelCheck {
  static let mostDigits = 6

  static func problems(inChart row: PanelRow, at path: String) -> [PanelProblem] {
    switch row {
    case .quotes(let quotes):
      guard !quotes.isEmpty else { return [PanelProblem("\(path).quotes", "is empty")] }
      return quotes.enumerated().flatMap { index, quote in
        let at = "\(path).quotes[\(index)]"
        return named(quote.name, at: "\(at).name") + digits(quote.digits, at: "\(at).digits")
      }
    case .line(let chart):
      let ranges =
        chart.ranges.isEmpty
        ? [PanelProblem("\(path).ranges", "is empty; give \"series\", or a field for some of 1d, 5d, 1m, 1y, 5y")] : []
      return ranges + digits(chart.style.digits, at: "\(path).digits")
    case .ruler(let ruler):
      return named(ruler.label, at: "\(path).label") + share(ruler.share, at: "\(path).share")
        + digits(ruler.style.digits, at: "\(path).digits")
    case .allocation(let allocation):
      var found = allocation.slices.isEmpty ? [PanelProblem("\(path).slices", "is empty")] : []
      for (index, slice) in allocation.slices.enumerated() {
        let at = "\(path).slices[\(index)]"
        found += named(slice.name, at: "\(at).name") + share(slice.actual, at: "\(at).actual")
        if let target = slice.target { found += share(target, at: "\(at).target") }
      }
      if let tolerance = allocation.tolerance { found += share(.fixed(tolerance), at: "\(path).tolerance") }
      return found + digits(allocation.style.digits, at: "\(path).digits")
    case .heat(let tiles):
      guard !tiles.isEmpty else { return [PanelProblem("\(path).tiles", "is empty")] }
      return tiles.enumerated().flatMap { index, tile in
        let at = "\(path).tiles[\(index)]"
        var found = named(tile.code, at: "\(at).code")
        if case .fixed(let weight) = tile.weight, !(weight > 0) {
          found.append(PanelProblem("\(at).weight", "\(weight) is not more than 0"))
        }
        return found
      }
    case .candles(let candles):
      return candles.lines.enumerated().flatMap { index, line in named(line.name, at: "\(path).lines[\(index)].name") }
        + digits(candles.digits, at: "\(path).digits")
    case .zones(let zones):
      var found: [PanelProblem] = []
      if zones.stops.count < 2 {
        found.append(PanelProblem("\(path).stops", "has \(zones.stops.count); give at least the two ends"))
      } else if zip(zones.stops, zones.stops.dropFirst()).contains(where: { $0 >= $1 }) {
        found.append(PanelProblem("\(path).stops", "must go up from the lowest to the highest"))
      }
      if zones.rows.isEmpty { found.append(PanelProblem("\(path).values", "is empty")) }
      for (index, row) in zones.rows.enumerated() { found += named(row.name, at: "\(path).values[\(index)].name") }
      return found + digits(zones.style.digits, at: "\(path).digits")
    case .sentence, .cells, .label, .list, .prominent, .bars, .picture, .items:
      return []
    }
  }

  private static func named(_ text: String, at path: String) -> [PanelProblem] {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [PanelProblem(path, "is empty")] : []
  }

  private static func share(_ number: PanelNumber, at path: String) -> [PanelProblem] {
    guard case .fixed(let value) = number else { return [] }
    return (0...1).contains(value) ? [] : [PanelProblem(path, "\(value) is not from 0 to 1")]
  }

  private static func digits(_ digits: Int?, at path: String) -> [PanelProblem] {
    guard let digits, !(0...mostDigits).contains(digits) else { return [] }
    return [PanelProblem(path, "\(digits) is not from 0 to \(mostDigits)")]
  }
}

extension PanelRow {
  /// Whether the row draws numbers rather than words.
  public var isChart: Bool {
    switch self {
    case .quotes, .line, .ruler, .allocation, .heat, .candles, .zones: true
    case .sentence, .cells, .label, .list, .prominent, .bars, .picture, .items: false
    }
  }
}
