/// A stretch of a video or audio item, or a passage of an article, that Loci picked out for the reader, with
/// why it is worth their time.
public struct KeyPoint: Hashable, Sendable {
  public let place: Place
  public let title: String
  public let reason: String

  public init(place: Place, title: String, reason: String) throws {
    if case .time(let span) = place, span.end == nil { throw ModelError("a key point has an end") }
    self.place = place
    self.title = try title.requiringText("key point title")
    self.reason = try reason.requiringText("key point reason")
  }

  public enum Place: Hashable, Sendable {
    /// From a sentence's start to a later sentence's end.
    case time(TimeSpan)
    case passage(Passage)
  }

  /// A passage of an article as `ArticlePassages` cuts it: a heading or a paragraph.
  public struct Passage: Hashable, Sendable {
    /// Counted from 1 at the top of the article.
    public let number: Int
    /// The passage's Markdown, as it is in the article.
    public let text: String

    public init(number: Int, text: String) throws {
      guard number >= 1 else { throw ModelError("passages are counted from 1") }
      self.number = number
      self.text = try text.requiringText("passage")
    }
  }

  public var span: TimeSpan? {
    if case .time(let span) = place { span } else { nil }
  }

  public var passage: Passage? {
    if case .passage(let passage) = place { passage } else { nil }
  }
}

/// The key points of one item, in order, and what they were picked with; the contents of `keypoints.json`.
public struct KeyPoints: Hashable, Sendable {
  public let points: [KeyPoint]
  public let choice: KeyPointChoice

  /// The points are all stretches of time or all passages, in order, and stretches do not overlap.
  public init(points: [KeyPoint], choice: KeyPointChoice) throws {
    guard let first = points.first else { throw ModelError("there are no key points") }
    let spans = points.compactMap(\.span)
    let passages = points.compactMap(\.passage)
    if first.span != nil {
      guard spans.count == points.count else { throw ModelError("key points mix times and passages") }
      for (earlier, later) in zip(spans, spans.dropFirst()) where later.start < (earlier.end ?? earlier.start) {
        throw ModelError("key points overlap or are out of time order")
      }
    } else {
      guard passages.count == points.count else { throw ModelError("key points mix times and passages") }
      for (earlier, later) in zip(passages, passages.dropFirst()) where later.number <= earlier.number {
        throw ModelError("key points are out of passage order")
      }
    }
    self.points = points
    self.choice = choice
  }
}

/// What key points are picked with: the model, and how many.
public struct KeyPointChoice: Hashable, Codable, Sendable {
  /// `nil`, or one no longer configured, follows the model chapters and key points are done with.
  public let model: ModelChoice?
  public let count: KeyPointCount

  public init(model: ModelChoice? = nil, count: KeyPointCount = .some) {
    self.model = model
    self.count = count
  }

  public static let standard = KeyPointChoice()
}

/// How many key points to pick.
public enum KeyPointCount: String, CaseIterable, Codable, Hashable, Sendable {
  case few, some, many

  public var range: ClosedRange<Int> {
    switch self {
    case .few: 3...4
    case .some: 4...6
    case .many: 6...8
    }
  }
}

/// How picking key points is going; `nil` on the page when nothing is being picked.
public enum KeyPointPicking: Hashable, Codable, Sendable {
  case running
  /// What went wrong; the key points picked before, if any, are kept.
  case failed(String)
}

/// The key points beside an item, as the panel shows them.
public struct KeyPointsPage: Hashable, Codable, Sendable {
  /// `nil` until they are picked.
  public let keyPoints: KeyPoints?
  public let picking: KeyPointPicking?
  /// What picking starts with: the choice made last on this host.
  public let choice: KeyPointChoice
  /// The model picking would use now; `nil` when the model services are not configured for it.
  public let model: ModelChoice?

  public init(keyPoints: KeyPoints?, picking: KeyPointPicking?, choice: KeyPointChoice, model: ModelChoice?) {
    self.keyPoints = keyPoints
    self.picking = picking
    self.choice = choice
    self.model = model
  }
}

extension KeyPoint: Codable {
  private enum CodingKeys: String, CodingKey {
    case start, end, passage, text, title, reason
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let title = try container.decode(String.self, forKey: .title)
    let reason = try container.decode(String.self, forKey: .reason)
    if let number = try container.decodeIfPresent(Int.self, forKey: .passage) {
      let text = try container.decode(String.self, forKey: .text)
      self = try decoder.validated {
        try KeyPoint(place: .passage(try Passage(number: number, text: text)), title: title, reason: reason)
      }
    } else {
      let start = Seconds.duration(try container.decode(Double.self, forKey: .start))
      let end = Seconds.duration(try container.decode(Double.self, forKey: .end))
      self = try decoder.validated {
        try KeyPoint(place: .time(try TimeSpan(start: start, end: end)), title: title, reason: reason)
      }
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch place {
    case .time(let span):
      try container.encode(Seconds.number(span.start), forKey: .start)
      try container.encode(Seconds.number(span.end ?? span.start), forKey: .end)
    case .passage(let passage):
      try container.encode(passage.number, forKey: .passage)
      try container.encode(passage.text, forKey: .text)
    }
    try container.encode(title, forKey: .title)
    try container.encode(reason, forKey: .reason)
  }
}

extension KeyPoints: Codable {
  private enum CodingKeys: String, CodingKey {
    case points, choice
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let points = try container.decode([KeyPoint].self, forKey: .points)
    let choice = try container.decodeIfPresent(KeyPointChoice.self, forKey: .choice) ?? .standard
    self = try decoder.validated { try KeyPoints(points: points, choice: choice) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(points, forKey: .points)
    try container.encode(choice, forKey: .choice)
  }
}
