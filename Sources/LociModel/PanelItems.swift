import Foundation

/// A stretch of items in a panel that the person and Loci both write in. Loci sets it up and decides whether
/// the person may add to it and tick its items; each item belongs to whoever wrote it.
public struct PanelItems: Hashable, Sendable {
  /// Stable within the panel, so edits and Loci's saves find the stretch again.
  public let id: String
  /// A small heading over the items, such as 「今天」.
  public let name: String?
  /// Whether the person may add items here.
  public let adds: Bool
  /// Whether items here have a circle to tick.
  public let checks: Bool
  public var items: [PanelItem]

  public init(id: String, name: String? = nil, adds: Bool = false, checks: Bool = false, items: [PanelItem]) {
    self.id = id
    self.name = name
    self.adds = adds
    self.checks = checks
    self.items = items
  }
}

/// One item in a panel. Its words belong to whoever wrote it; whether it is pinned and the person's note on it
/// belong to the person, whoever wrote it.
public struct PanelItem: Hashable, Sendable, Identifiable {
  /// Stable within the panel.
  public let id: String
  public var text: String
  public var by: Author
  /// Loci suggests it and the person has not taken it yet.
  public var proposed: Bool
  public var done: Bool
  public var pinned: Bool
  /// The person's note, shown under the item.
  public var note: String?
  /// A few words from Loci on why it is there; only on Loci's items, and the person's note shows instead.
  public var why: String?

  public enum Author: String, Hashable, Codable, Sendable {
    case you, loci
  }

  public init(
    id: String, text: String, by: Author, proposed: Bool = false, done: Bool = false, pinned: Bool = false,
    note: String? = nil, why: String? = nil
  ) {
    self.id = id
    self.text = text
    self.by = by
    self.proposed = proposed
    self.done = done
    self.pinned = pinned
    self.note = note
    self.why = why
  }

  /// The person's item with these words, as they write it into a panel.
  public static func yours(id: String, text: String) -> PanelItem {
    PanelItem(id: id, text: text, by: .you)
  }

  /// The item made the person's own: Loci no longer replaces it.
  public var taken: PanelItem {
    var taken = self
    taken.by = .you
    taken.proposed = false
    taken.why = nil
    return taken
  }
}

extension PanelItems: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, name, adds, checks, items
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    adds = try container.decodeIfPresent(Bool.self, forKey: .adds) ?? false
    checks = try container.decodeIfPresent(Bool.self, forKey: .checks) ?? false
    items = try container.decodeIfPresent([PanelItem].self, forKey: .items) ?? []
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(name, forKey: .name)
    if adds { try container.encode(adds, forKey: .adds) }
    if checks { try container.encode(checks, forKey: .checks) }
    try container.encode(items, forKey: .items)
  }
}

extension PanelItem: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, text, by, proposed, done, pinned, note, why
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    text = try container.decode(String.self, forKey: .text)
    by = try container.decodeIfPresent(Author.self, forKey: .by) ?? .loci
    proposed = try container.decodeIfPresent(Bool.self, forKey: .proposed) ?? false
    done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
    pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    note = try container.decodeIfPresent(String.self, forKey: .note)
    why = try container.decodeIfPresent(String.self, forKey: .why)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(text, forKey: .text)
    if by == .you { try container.encode(by, forKey: .by) }
    if proposed { try container.encode(proposed, forKey: .proposed) }
    if done { try container.encode(done, forKey: .done) }
    if pinned { try container.encode(pinned, forKey: .pinned) }
    try container.encodeIfPresent(note, forKey: .note)
    try container.encodeIfPresent(why, forKey: .why)
  }
}

/// Where an item is in a panel.
public struct PanelItemPlace: Hashable, Sendable {
  public let item: PanelItem
  public let section: String
  public let index: Int
}

extension Panel {
  /// Every stretch of items, top to bottom and page by page.
  public var sections: [PanelItems] {
    rowsOfEveryPage.flatMap { rows in
      rows.compactMap { row in
        if case .items(let items) = row { items } else { nil }
      }
    }
  }

  public func place(of id: String) -> PanelItemPlace? {
    for section in sections {
      if let index = section.items.firstIndex(where: { $0.id == id }) {
        return PanelItemPlace(item: section.items[index], section: section.id, index: index)
      }
    }
    return nil
  }

  /// The panel with each stretch of items changed, everything else as it is.
  public func changingSections(_ change: (inout PanelItems) throws(PanelProblems) -> Void) throws(PanelProblems)
    -> Panel
  {
    func changed(_ rows: [PanelRow]) throws(PanelProblems) -> [PanelRow] {
      var result: [PanelRow] = []
      for row in rows {
        guard case .items(var section) = row else {
          result.append(row)
          continue
        }
        try change(&section)
        result.append(.items(section))
      }
      return result
    }
    let body: PanelBody
    switch self.body {
    case .rows(let rows): body = .rows(try changed(rows))
    case .pages(let pages):
      var changedPages: [PanelPage] = []
      for page in pages { changedPages.append(PanelPage(name: page.name, rows: try changed(page.rows))) }
      body = .pages(changedPages)
    }
    return with(body: body)
  }

  /// The rows of each page, or the one stack of rows of a panel that does not page.
  public var rowsOfEveryPage: [[PanelRow]] {
    switch body {
    case .rows(let rows): [rows]
    case .pages(let pages): pages.map(\.rows)
    }
  }
}
