import Foundation

/// A panel Loci keeps beside the main conversation, as Loci wrote it in `agent/panels/<name>.json`.
public struct Panel: Hashable, Codable, Sendable, Identifiable {
  /// The file's name without `.json`; unique among panels.
  public let name: String
  public let title: String
  /// The sites the panel reads, by domain, shown as small icons before its title.
  public let sources: [String]
  /// What the person asked Loci to follow; a refresh runs it again.
  public let follow: String
  /// `nil` when the panel only changes when Loci or the person asks.
  public let refresh: PanelRefresh?
  public let body: PanelBody

  public var id: String { name }

  public init(
    name: String, title: String, sources: [String] = [], follow: String, refresh: PanelRefresh? = nil,
    body: PanelBody
  ) {
    self.name = name
    self.title = title
    self.sources = sources
    self.follow = follow
    self.refresh = refresh
    self.body = body
  }

  private enum CodingKeys: String, CodingKey {
    case name, title, sources, follow, refresh, rows, pages
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    title = try container.decode(String.self, forKey: .title)
    sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
    follow = try container.decode(String.self, forKey: .follow)
    refresh = try container.decodeIfPresent(PanelRefresh.self, forKey: .refresh)
    if let pages = try container.decodeIfPresent([PanelPage].self, forKey: .pages) {
      body = .pages(pages)
    } else {
      body = .rows(try container.decode([PanelRow].self, forKey: .rows))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(title, forKey: .title)
    try container.encode(sources, forKey: .sources)
    try container.encode(follow, forKey: .follow)
    try container.encodeIfPresent(refresh, forKey: .refresh)
    switch body {
    case .rows(let rows): try container.encode(rows, forKey: .rows)
    case .pages(let pages): try container.encode(pages, forKey: .pages)
    }
  }
}

/// What a panel shows under its title: one stack of rows, or pages the person turns with arrows.
public enum PanelBody: Hashable, Sendable {
  case rows([PanelRow])
  case pages([PanelPage])
}

/// One page of a panel that pages, named in the bar between its arrows.
public struct PanelPage: Hashable, Codable, Sendable {
  public let name: String
  public let rows: [PanelRow]

  public init(name: String, rows: [PanelRow]) {
    self.name = name
    self.rows = rows
  }
}

/// How often a panel is refreshed in the background, in the person's time zone.
public struct PanelRefresh: Hashable, Codable, Sendable {
  public let every: Every
  /// `"HH:mm"`; for `day` and `week`, the time of day it is refreshed.
  public let at: String?
  /// `1` is Sunday, as `Calendar` counts; only for `week`.
  public let weekday: Int?

  public enum Every: String, Hashable, Codable, Sendable {
    case hour, day, week
  }

  public init(every: Every, at: String? = nil, weekday: Int? = nil) {
    self.every = every
    self.at = at
    self.weekday = weekday
  }
}

/// One row of a panel. Each row is a fixed component the app draws natively; Loci only fills it.
public enum PanelRow: Hashable, Sendable {
  /// One sentence, with `**bold**` spans; a panel starts with one that sums it up.
  case sentence(String)
  /// Two or three small cells side by side, each a label over a large value.
  case cells([PanelCell])
  /// A small heading over the rows below it.
  case label(String)
  case list([PanelListItem])
  /// One thing that matters most, in large type.
  case prominent(title: String, subtitle: String?)
  /// Horizontal bars to compare a few quantities.
  case bars([PanelBar])
  case picture(URL, link: URL?)
  /// Items the person and Loci both write in, such as a day's to-dos.
  case items(PanelItems)
  case quotes([PanelQuote])
  case line(PanelLineChart)
  case ruler(PanelRuler)
  case allocation(PanelAllocation)
  case heat([PanelHeatTile])
  case candles(PanelCandles)
  case zones(PanelZones)
}

public struct PanelCell: Hashable, Codable, Sendable {
  public let label: String
  public let value: String
  /// A few words after the value, such as when it happened.
  public let note: String?

  public init(label: String, value: String, note: String? = nil) {
    self.label = label
    self.value = value
    self.note = note
  }
}

/// One line of a list: a title, and whatever of the rest Loci has for it.
public struct PanelListItem: Hashable, Codable, Sendable {
  public let title: String
  public let subtitle: String?
  /// When it happened, in a few words: 「昨天」, 「周二」.
  public let at: String?
  /// A rank shown before the title.
  public let number: Int?
  /// A picture shown before the title.
  public let cover: URL?
  /// How far along it is, from 0 to 1, shown as a thin bar under the title.
  public let progress: Double?
  /// Clicking the line opens this: a web page in the built-in browser, or a `loci://` place.
  public let link: URL?
  /// When set, the line has an 「问 Loci」 button that sends this to the main conversation.
  public let ask: String?

  public init(
    title: String, subtitle: String? = nil, at: String? = nil, number: Int? = nil, cover: URL? = nil,
    progress: Double? = nil, link: URL? = nil, ask: String? = nil
  ) {
    self.title = title
    self.subtitle = subtitle
    self.at = at
    self.number = number
    self.cover = cover
    self.progress = progress
    self.link = link
    self.ask = ask
  }
}

public struct PanelBar: Hashable, Codable, Sendable {
  public let name: String
  /// The bar's length, from 0 to 1.
  public let fraction: Double
  /// The value written after the bar.
  public let value: String

  public init(name: String, fraction: Double, value: String) {
    self.name = name
    self.fraction = fraction
    self.value = value
  }
}

extension PanelRow: Codable {
  private enum CodingKeys: String, CodingKey {
    case row, text, cells, items, title, subtitle, bars, url, link, quotes, tiles
  }

  private enum Kind: String, Codable {
    case sentence, cells, label, list, prominent, bars, picture, items, quotes, line, ruler, allocation, heat,
      candles, zones
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .row) {
    case .sentence: self = .sentence(try container.decode(String.self, forKey: .text))
    case .cells: self = .cells(try container.decode([PanelCell].self, forKey: .cells))
    case .label: self = .label(try container.decode(String.self, forKey: .text))
    case .list: self = .list(try container.decode([PanelListItem].self, forKey: .items))
    case .prominent:
      self = .prominent(
        title: try container.decode(String.self, forKey: .title),
        subtitle: try container.decodeIfPresent(String.self, forKey: .subtitle))
    case .bars: self = .bars(try container.decode([PanelBar].self, forKey: .bars))
    case .picture:
      self = .picture(
        try container.decode(URL.self, forKey: .url), link: try container.decodeIfPresent(URL.self, forKey: .link))
    case .items: self = .items(try PanelItems(from: decoder))
    case .quotes: self = .quotes(try container.decode([PanelQuote].self, forKey: .quotes))
    case .line: self = .line(try PanelLineChart(from: decoder))
    case .ruler: self = .ruler(try PanelRuler(from: decoder))
    case .allocation: self = .allocation(try PanelAllocation(from: decoder))
    case .heat: self = .heat(try container.decode([PanelHeatTile].self, forKey: .tiles))
    case .candles: self = .candles(try PanelCandles(from: decoder))
    case .zones: self = .zones(try PanelZones(from: decoder))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .sentence(let text):
      try container.encode(Kind.sentence, forKey: .row)
      try container.encode(text, forKey: .text)
    case .cells(let cells):
      try container.encode(Kind.cells, forKey: .row)
      try container.encode(cells, forKey: .cells)
    case .label(let text):
      try container.encode(Kind.label, forKey: .row)
      try container.encode(text, forKey: .text)
    case .list(let items):
      try container.encode(Kind.list, forKey: .row)
      try container.encode(items, forKey: .items)
    case .prominent(let title, let subtitle):
      try container.encode(Kind.prominent, forKey: .row)
      try container.encode(title, forKey: .title)
      try container.encodeIfPresent(subtitle, forKey: .subtitle)
    case .bars(let bars):
      try container.encode(Kind.bars, forKey: .row)
      try container.encode(bars, forKey: .bars)
    case .picture(let url, let link):
      try container.encode(Kind.picture, forKey: .row)
      try container.encode(url, forKey: .url)
      try container.encodeIfPresent(link, forKey: .link)
    case .items(let items):
      try container.encode(Kind.items, forKey: .row)
      try items.encode(to: encoder)
    case .quotes(let quotes):
      try container.encode(Kind.quotes, forKey: .row)
      try container.encode(quotes, forKey: .quotes)
    case .line(let chart):
      try container.encode(Kind.line, forKey: .row)
      try chart.encode(to: encoder)
    case .ruler(let ruler):
      try container.encode(Kind.ruler, forKey: .row)
      try ruler.encode(to: encoder)
    case .allocation(let allocation):
      try container.encode(Kind.allocation, forKey: .row)
      try allocation.encode(to: encoder)
    case .heat(let tiles):
      try container.encode(Kind.heat, forKey: .row)
      try container.encode(tiles, forKey: .tiles)
    case .candles(let candles):
      try container.encode(Kind.candles, forKey: .row)
      try candles.encode(to: encoder)
    case .zones(let zones):
      try container.encode(Kind.zones, forKey: .row)
      try zones.encode(to: encoder)
    }
  }
}

/// The panels beside the main conversation, top to bottom, in the order the person left them.
public struct PanelColumn: Hashable, Codable, Sendable {
  public let slots: [PanelSlot]
  /// Panels being refreshed in the background right now: the column's own by name, a pinned one by
  /// `PanelRef.key`.
  public let refreshing: Set<String>
  /// The person's take on lines of the panels' lists, keyed as `refreshing` is.
  public let marks: [String: [PanelLineKey: PanelLineMark]]
  /// The snapshots of the sources the panels' rows point at.
  public let readings: PanelReadings

  public init(
    slots: [PanelSlot], refreshing: Set<String> = [], marks: [String: [PanelLineKey: PanelLineMark]] = [:],
    readings: PanelReadings = PanelReadings()
  ) {
    self.slots = slots
    self.refreshing = refreshing
    self.marks = marks
    self.readings = readings
  }
}

/// One place in the panel column: the app's own 「接着读」, or a panel Loci keeps.
public enum PanelSlot: Hashable, Codable, Sendable {
  /// Items read partway, most recently read first; the column leaves this slot out when there are none.
  case reading([ReadingNow])
  case panel(Panel)
  /// A project's panel pinned to the chat's column: the same panel, refreshed and edited in the project.
  case pinned(Project.ID, Panel)
}

/// An item read partway, as 「接着读」 lists it.
public struct ReadingNow: Hashable, Codable, Sendable {
  public let item: Item
  /// How far along it is, from 0 to 1.
  public let progress: Double
  /// Minutes left at the reader's pace or the media's length; `nil` when it cannot be told.
  public let minutesLeft: Int?

  public init(item: Item, progress: Double, minutesLeft: Int? = nil) {
    self.item = item
    self.progress = progress
    self.minutesLeft = minutesLeft
  }
}
