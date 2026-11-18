/// The chapters of a video or audio item and the stretches worth hearing; the contents of `outline.json`.
public struct Outline: Hashable, Sendable {
  /// In time order.
  public let chapters: [Chapter]
  public let highlights: [Highlight]

  public init(chapters: [Chapter], highlights: [Highlight]) throws {
    for (earlier, later) in zip(chapters, chapters.dropFirst()) where later.start < earlier.start {
      throw ModelError("chapters are out of time order")
    }
    self.chapters = chapters
    self.highlights = highlights
  }

  public struct Chapter: Hashable, Sendable {
    public let start: Duration
    public let title: String

    public init(start: Duration, title: String) throws {
      guard start >= .zero else { throw ModelError("chapter starts before zero") }
      self.start = .milliseconds(start.roundedMilliseconds)
      self.title = try title.requiringText("chapter title")
    }
  }

  /// A stretch Loci picked out, with why it is worth hearing.
  public struct Highlight: Hashable, Codable, Sendable {
    public let span: TimeSpan
    public let title: String
    public let reason: String

    public init(span: TimeSpan, title: String, reason: String) throws {
      guard span.end != nil else { throw ModelError("a highlight has an end") }
      self.span = span
      self.title = try title.requiringText("highlight title")
      self.reason = try reason.requiringText("highlight reason")
    }

    private enum CodingKeys: String, CodingKey {
      case start, end, title, reason
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let start = Seconds.duration(try container.decode(Double.self, forKey: .start))
      let end = Seconds.duration(try container.decode(Double.self, forKey: .end))
      let title = try container.decode(String.self, forKey: .title)
      let reason = try container.decode(String.self, forKey: .reason)
      self = try decoder.validated {
        try Highlight(span: try TimeSpan(start: start, end: end), title: title, reason: reason)
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(Seconds.number(span.start), forKey: .start)
      try container.encode(Seconds.number(span.end ?? span.start), forKey: .end)
      try container.encode(title, forKey: .title)
      try container.encode(reason, forKey: .reason)
    }
  }
}

extension Outline: Codable {
  private enum CodingKeys: String, CodingKey {
    case chapters, highlights
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
    let highlights = try container.decodeIfPresent([Highlight].self, forKey: .highlights) ?? []
    self = try decoder.validated { try Outline(chapters: chapters, highlights: highlights) }
  }
}

extension Outline.Chapter: Codable {
  private enum CodingKeys: String, CodingKey {
    case start, title
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let start = Seconds.duration(try container.decode(Double.self, forKey: .start))
    let title = try container.decode(String.self, forKey: .title)
    self = try decoder.validated { try Outline.Chapter(start: start, title: title) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Seconds.number(start), forKey: .start)
    try container.encode(title, forKey: .title)
  }
}
