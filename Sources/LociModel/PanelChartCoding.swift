import Foundation

/// Chart rows write their style beside their own keys: `{ "row": "ruler", ..., "format": "percent" }`.
extension PanelLineChart: Codable {
  private enum CodingKeys: String, CodingKey { case value, change, series, ranges }

  /// `series` is one field cut to every span; `ranges` names a field for each span it has.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    value = try container.decode(PanelNumber.self, forKey: .value)
    change = try container.decodeIfPresent(PanelNumber.self, forKey: .change)
    if let series = try container.decodeIfPresent(SourceField.self, forKey: .series) {
      ranges = Dictionary(uniqueKeysWithValues: PanelRange.allCases.map { ($0, series) })
    } else {
      ranges = try container.decode([PanelRange: SourceField].self, forKey: .ranges)
    }
    style = try PanelStyle(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(value, forKey: .value)
    try container.encodeIfPresent(change, forKey: .change)
    let fields = Set(ranges.values)
    if fields.count == 1, let series = fields.first, ranges.count == PanelRange.allCases.count {
      try container.encode(series, forKey: .series)
    } else {
      try container.encode(ranges, forKey: .ranges)
    }
    try style.encode(to: encoder)
  }
}

extension PanelRuler: Codable {
  private enum CodingKeys: String, CodingKey { case label, value, share, low, high }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    label = try container.decode(String.self, forKey: .label)
    value = try container.decode(PanelNumber.self, forKey: .value)
    share = try container.decode(PanelNumber.self, forKey: .share)
    low = try container.decode(PanelNumber.self, forKey: .low)
    high = try container.decode(PanelNumber.self, forKey: .high)
    style = try PanelStyle(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(label, forKey: .label)
    try container.encode(value, forKey: .value)
    try container.encode(share, forKey: .share)
    try container.encode(low, forKey: .low)
    try container.encode(high, forKey: .high)
    try style.encode(to: encoder)
  }
}

extension PanelAllocation: Codable {
  private enum CodingKeys: String, CodingKey { case total, change, slices, tolerance }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    total = try container.decodeIfPresent(PanelNumber.self, forKey: .total)
    change = try container.decodeIfPresent(PanelNumber.self, forKey: .change)
    slices = try container.decode([PanelSlice].self, forKey: .slices)
    tolerance = try container.decodeIfPresent(Double.self, forKey: .tolerance)
    style = try PanelStyle(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(total, forKey: .total)
    try container.encodeIfPresent(change, forKey: .change)
    try container.encode(slices, forKey: .slices)
    try container.encodeIfPresent(tolerance, forKey: .tolerance)
    try style.encode(to: encoder)
  }
}

extension PanelZones: Codable {
  private enum CodingKeys: String, CodingKey { case stops, values }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    stops = try container.decode([Double].self, forKey: .stops)
    rows = try container.decode([PanelZoneRow].self, forKey: .values)
    style = try PanelStyle(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(stops, forKey: .stops)
    try container.encode(rows, forKey: .values)
    try style.encode(to: encoder)
  }
}
