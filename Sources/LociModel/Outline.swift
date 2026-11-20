/// The chapters of a video or audio item; the contents of `outline.json`.
public struct Outline: Hashable, Sendable {
  /// In time order.
  public let chapters: [Chapter]

  public init(chapters: [Chapter]) throws {
    for (earlier, later) in zip(chapters, chapters.dropFirst()) where later.start < earlier.start {
      throw ModelError("chapters are out of time order")
    }
    self.chapters = chapters
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
}

extension Outline: Codable {
  private enum CodingKeys: String, CodingKey {
    case chapters
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
    self = try decoder.validated { try Outline(chapters: chapters) }
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
