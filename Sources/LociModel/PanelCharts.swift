import Foundation

/// A number a chart row shows: written as a number it is fixed; written as `"<source>.<record>.<field>"`
/// the app fills it from the source, and it never passes through Loci.
public enum PanelNumber: Hashable, Sendable {
  case fixed(Double)
  case field(SourceField)

  public var field: SourceField? {
    if case .field(let field) = self { field } else { nil }
  }
}

extension PanelNumber: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Double.self) {
      self = .fixed(number)
      return
    }
    let text = try container.decode(String.self)
    guard let field = SourceField(text) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "\"\(text)\" is not a number or <source>.<record>.<field>")
    }
    self = .field(field)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .fixed(let number): try container.encode(number)
    case .field(let field): try container.encode(field)
    }
  }
}

/// Words a chart row shows: written as text they are fixed; written as `{ "field": "<source>.<record>.<field>" }`
/// the app fills them from the source, such as a fund's latest net value date.
public enum PanelText: Hashable, Sendable {
  case fixed(String)
  case field(SourceField)
}

extension PanelText: Codable {
  private enum CodingKeys: String, CodingKey { case field }

  public init(from decoder: any Decoder) throws {
    if let text = try? decoder.singleValueContainer().decode(String.self) {
      self = .fixed(text)
    } else {
      self = .field(try decoder.container(keyedBy: CodingKeys.self).decode(SourceField.self, forKey: .field))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .fixed(let text):
      var container = encoder.singleValueContainer()
      try container.encode(text)
    case .field(let field):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(field, forKey: .field)
    }
  }
}

/// How a row writes its numbers: `number` as they are, `percent` as a share (0.159 is 15.90%), with
/// `digits` after the point and a `unit` after the number.
public struct PanelStyle: Hashable, Codable, Sendable {
  public let format: Format
  public let digits: Int?
  public let unit: String?

  public enum Format: String, Hashable, Codable, Sendable {
    case number, percent
  }

  public init(format: Format = .number, digits: Int? = nil, unit: String? = nil) {
    self.format = format
    self.digits = digits
    self.unit = unit
  }

  private enum CodingKeys: String, CodingKey { case format, digits, unit }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    format = try container.decodeIfPresent(Format.self, forKey: .format) ?? .number
    digits = try container.decodeIfPresent(Int.self, forKey: .digits)
    unit = try container.decodeIfPresent(String.self, forKey: .unit)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if format != .number { try container.encode(format, forKey: .format) }
    try container.encodeIfPresent(digits, forKey: .digits)
    try container.encodeIfPresent(unit, forKey: .unit)
  }
}

/// One line of a quotes row: name, price, a small line of the day, and the change in a red or green block.
public struct PanelQuote: Hashable, Codable, Sendable {
  public let name: String
  /// The code, under the name.
  public let code: String?
  public let price: PanelNumber
  /// From 0: `-0.0186` is −1.86%.
  public let change: PanelNumber?
  /// A points field drawn as the small line.
  public let spark: SourceField?
  /// For a fund priced once a day, the day of the net value, written after the code.
  public let asOf: PanelText?
  public let digits: Int?

  public init(
    name: String, code: String? = nil, price: PanelNumber, change: PanelNumber? = nil, spark: SourceField? = nil,
    asOf: PanelText? = nil, digits: Int? = nil
  ) {
    self.name = name
    self.code = code
    self.price = price
    self.change = change
    self.spark = spark
    self.asOf = asOf
    self.digits = digits
  }
}

/// The spans a line chart switches between.
public enum PanelRange: String, Hashable, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
  case day = "1d"
  case fiveDays = "5d"
  case month = "1m"
  case year = "1y"
  case fiveYears = "5y"

  /// How far back the span reaches from the newest point.
  public var milliseconds: Int64 {
    let day: Int64 = 86_400_000
    return switch self {
    case .day: day
    case .fiveDays: 5 * day
    case .month: 31 * day
    case .year: 366 * day
    case .fiveYears: 5 * 366 * day
    }
  }
}

/// A large number over a line, with spans to switch between and a crosshair on hover.
public struct PanelLineChart: Hashable, Sendable {
  public let value: PanelNumber
  public let change: PanelNumber?
  /// What each span draws: one field cut to each span, or a field for each.
  public let ranges: [PanelRange: SourceField]
  public let style: PanelStyle

  public init(
    value: PanelNumber, change: PanelNumber? = nil, ranges: [PanelRange: SourceField], style: PanelStyle = PanelStyle()
  ) {
    self.value = value
    self.change = change
    self.ranges = ranges
    self.style = style
  }

  /// The spans the chart offers, shortest first.
  public var spans: [PanelRange] { PanelRange.allCases.filter { ranges[$0] != nil } }
}

/// Where a value stands in its history: a ruler with the lowest and highest at its ends.
public struct PanelRuler: Hashable, Sendable {
  public let label: String
  public let value: PanelNumber
  /// Where it stands, from 0 at the lowest to 1 at the highest.
  public let share: PanelNumber
  public let low: PanelNumber
  public let high: PanelNumber
  /// How the value and the ends are written.
  public let style: PanelStyle

  public init(
    label: String, value: PanelNumber, share: PanelNumber, low: PanelNumber, high: PanelNumber,
    style: PanelStyle = PanelStyle()
  ) {
    self.label = label
    self.value = value
    self.share = share
    self.low = low
    self.high = high
    self.style = style
  }
}

/// Shares held against shares meant: a ring of what is, a thin ring of what was meant, a line for each.
public struct PanelAllocation: Hashable, Sendable {
  /// The amount in the ring's middle, written in `style`.
  public let total: PanelNumber?
  public let change: PanelNumber?
  public let slices: [PanelSlice]
  /// How far from its target a share may drift before it is marked; 0.01 when not given.
  public let tolerance: Double?
  public let style: PanelStyle

  public init(
    total: PanelNumber? = nil, change: PanelNumber? = nil, slices: [PanelSlice], tolerance: Double? = nil,
    style: PanelStyle = PanelStyle()
  ) {
    self.total = total
    self.change = change
    self.slices = slices
    self.tolerance = tolerance
    self.style = style
  }

  public static let defaultTolerance = 0.01

  /// Whether the slice has drifted from its target by more than the tolerance.
  public func drifted(actual: Double, target: Double?) -> Bool {
    guard let target else { return false }
    return abs(actual - target) > (tolerance ?? Self.defaultTolerance) + 1e-9
  }
}

public struct PanelSlice: Hashable, Codable, Sendable {
  public let name: String
  /// From 0 to 1.
  public let actual: PanelNumber
  public let target: PanelNumber?

  public init(name: String, actual: PanelNumber, target: PanelNumber? = nil) {
    self.name = name
    self.actual = actual
    self.target = target
  }
}

/// A tile of a heat map: its size by weight, its colour by change.
public struct PanelHeatTile: Hashable, Codable, Sendable {
  public let code: String
  public let weight: PanelNumber
  public let change: PanelNumber

  public init(code: String, weight: PanelNumber, change: PanelNumber) {
    self.code = code
    self.weight = weight
    self.change = change
  }
}

/// Candles, with the prices the person or Loci set to take profit or stop a loss drawn as dashed lines.
public struct PanelCandles: Hashable, Codable, Sendable {
  public let series: SourceField
  public let lines: [PanelPriceLine]
  public let digits: Int?

  public init(series: SourceField, lines: [PanelPriceLine] = [], digits: Int? = nil) {
    self.series = series
    self.lines = lines
    self.digits = digits
  }

  private enum CodingKeys: String, CodingKey { case series, lines, digits }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    series = try container.decode(SourceField.self, forKey: .series)
    lines = try container.decodeIfPresent([PanelPriceLine].self, forKey: .lines) ?? []
    digits = try container.decodeIfPresent(Int.self, forKey: .digits)
  }
}

/// A price drawn across candles: where to take profit, drawn red, or where to stop a loss, drawn green.
public struct PanelPriceLine: Hashable, Codable, Sendable {
  public let name: String
  public let price: PanelNumber
  public let kind: Kind

  public enum Kind: String, Hashable, Codable, Sendable {
    case take, stop
  }

  public init(name: String, price: PanelNumber, kind: Kind) {
    self.name = name
    self.price = price
    self.kind = kind
  }
}

/// A bar cut into zones, such as a premium's 0–3–10–20%, with where each line's value falls.
public struct PanelZones: Hashable, Sendable {
  /// Where the zones meet, lowest first; the bar runs from the first to the last.
  public let stops: [Double]
  public let rows: [PanelZoneRow]
  public let style: PanelStyle

  public init(stops: [Double], rows: [PanelZoneRow], style: PanelStyle = PanelStyle()) {
    self.stops = stops
    self.rows = rows
    self.style = style
  }
}

public struct PanelZoneRow: Hashable, Codable, Sendable {
  public let name: String
  /// A few words under the name.
  public let note: String?
  public let value: PanelNumber

  public init(name: String, note: String? = nil, value: PanelNumber) {
    self.name = name
    self.note = note
    self.value = value
  }
}
