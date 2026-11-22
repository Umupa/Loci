import Foundation

/// A course's atlas: one page drawn from the subject's own structure, its gist and the blocks under it, which
/// grows as the person reads. The companion writes it; the app lays it out.
public struct CourseAtlas: Hashable, Codable, Sendable {
  public let gist: AtlasText
  public let blocks: [AtlasBlock]

  public init(gist: AtlasText, blocks: [AtlasBlock]) throws {
    self.gist = gist
    self.blocks = blocks
    try validate()
  }

  /// The lessons it has a dive for.
  public var dives: [Lesson.ID] {
    blocks.compactMap { if case .dive(let dive) = $0 { dive.lesson } else { nil } }
  }

  /// Every lesson the atlas points at.
  public var lessons: Set<Lesson.ID> {
    Set(blocks.flatMap(\.lessons))
  }

  /// Throws when the atlas points at a lesson that is not in `plan`.
  public func check(against plan: [Lesson]) throws {
    let known = Set(plan.map(\.id))
    let unknown = lessons.subtracting(known).map(\.description).sorted()
    guard unknown.isEmpty else {
      throw ModelError("use lesson IDs from loci course plan; not in the plan: \(unknown.joined(separator: ", "))")
    }
  }

  private func validate() throws {
    guard (1...16).contains(blocks.count) else { throw ModelError("an atlas has 1 to 16 blocks") }
    for (index, block) in blocks.enumerated() {
      do {
        try block.validate()
      } catch let error as ModelError {
        throw ModelError("block \(index + 1) (\(block.kind)): \(error.description)")
      }
    }
    let dives = dives.map(\.description)
    if let repeated = dives.first(where: { lesson in dives.count { $0 == lesson } > 1 }) {
      throw ModelError("give lesson \(repeated) one dive")
    }
  }

  private enum CodingKeys: String, CodingKey {
    case gist, blocks
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let gist = try values.decode(AtlasText.self, forKey: .gist)
    let blocks = try values.decode([AtlasBlock].self, forKey: .blocks)
    self = try decoder.validated { try CourseAtlas(gist: gist, blocks: blocks) }
  }
}

/// One line of an atlas. `**strong**` and `` `code` `` are the only marks.
public struct AtlasText: Hashable, Codable, Sendable, CustomStringConvertible {
  public let description: String

  public init(_ text: String) throws {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 280, !trimmed.contains(where: \.isNewline) else {
      throw ModelError("each text in the atlas is one line of 1 to 280 characters: \(trimmed.prefix(60))")
    }
    description = trimmed
  }

  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    self = try decoder.validated { try AtlasText(text) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

/// A part of an atlas, written as a JSON object whose `kind` names it.
public enum AtlasBlock: Hashable, Codable, Sendable {
  /// A row of quantities: what the subject must achieve, and how much.
  case figures([AtlasFigure])
  /// A path the subject takes, step by step.
  case flow(AtlasFlow)
  /// Columns of stacked layers, the layer that matters in each marked: a cross-section compared.
  case layers(AtlasLayers)
  /// A few side-by-side cards: mechanisms, trade-offs, foundations.
  case cards(AtlasCards)
  /// What one lesson taught, as a flow and what to keep.
  case dive(AtlasDive)
  /// A comparison: one column per system, one row per choice.
  case table(AtlasTable)

  public var kind: String {
    switch self {
    case .figures: "figures"
    case .flow: "flow"
    case .layers: "layers"
    case .cards: "cards"
    case .dive: "dive"
    case .table: "table"
    }
  }

  public var lessons: [Lesson.ID] {
    switch self {
    case .figures: []
    case .flow(let flow): flow.lessons + flow.steps.flatMap(\.lessons)
    case .layers(let layers): layers.lessons
    case .cards(let cards): cards.lessons + cards.cards.flatMap(\.lessons)
    case .dive(let dive): [dive.lesson]
    case .table(let table): table.lessons + table.rows.flatMap(\.lessons)
    }
  }

  func validate() throws {
    switch self {
    case .figures(let figures): try Self.count(figures, 2...5, "figures")
    case .flow(let flow):
      try Self.count(flow.steps, 2...6, "steps")
      try flow.steps.forEach { try Self.count($0.points, 0...4, "points in a step") }
    case .layers(let layers):
      try Self.count(layers.columns, 2...4, "columns")
      try layers.columns.forEach { try Self.count($0.layers, 2...6, "layers in a column") }
    case .cards(let cards):
      try Self.count(cards.cards, 1...4, "cards")
      try cards.cards.forEach { try Self.count($0.points, 1...5, "points in a card") }
    case .dive(let dive):
      try Self.count(dive.steps, 2...6, "steps")
      try Self.count(dive.keep, 0...3, "things to keep")
    case .table(let table):
      try Self.count(table.columns, 2...5, "columns")
      try Self.count(table.rows, 1...16, "rows")
      if let row = table.rows.first(where: { $0.cells.count != table.columns.count }) {
        throw ModelError("row \(row.label) needs one cell per column, null for one not known yet")
      }
    }
  }

  private static func count<Value>(_ values: [Value], _ range: ClosedRange<Int>, _ what: String) throws {
    guard range.contains(values.count) else {
      throw ModelError("give \(range.lowerBound) to \(range.upperBound) \(what), not \(values.count)")
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind, figures
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(String.self, forKey: .kind)
    switch kind {
    case "figures": self = .figures(try values.decode([AtlasFigure].self, forKey: .figures))
    case "flow": self = .flow(try AtlasFlow(from: decoder))
    case "layers": self = .layers(try AtlasLayers(from: decoder))
    case "cards": self = .cards(try AtlasCards(from: decoder))
    case "dive": self = .dive(try AtlasDive(from: decoder))
    case "table": self = .table(try AtlasTable(from: decoder))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: values,
        debugDescription: "kind is one of figures, flow, layers, cards, dive, table; not \(kind)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(kind, forKey: .kind)
    switch self {
    case .figures(let figures): try values.encode(figures, forKey: .figures)
    case .flow(let flow): try flow.encode(to: encoder)
    case .layers(let layers): try layers.encode(to: encoder)
    case .cards(let cards): try cards.encode(to: encoder)
    case .dive(let dive): try dive.encode(to: encoder)
    case .table(let table): try table.encode(to: encoder)
    }
  }
}
