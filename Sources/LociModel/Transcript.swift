/// What is said in a video or audio item, sentence by sentence, with times; the contents of
/// `transcript.json`.
public struct Transcript: Hashable, Sendable {
  /// A BCP 47 tag for the spoken language; `nil` when it was not detected.
  public let language: String?
  public let origin: Origin
  /// In time order.
  public let segments: [Segment]

  public init(language: String?, origin: Origin, segments: [Segment]) throws {
    for (earlier, later) in zip(segments, segments.dropFirst()) where later.start < earlier.start {
      throw ModelError("segments are out of time order")
    }
    self.language = language
    self.origin = origin
    self.segments = segments
  }

  /// Where the text came from.
  public enum Origin: Hashable, Sendable {
    /// The site's own subtitles.
    case platform
    /// Recognized on this Mac with this model.
    case recognized(SpeechModel)
  }

  /// One sentence or short line, spoken from `start` to `end`.
  public struct Segment: Hashable, Sendable {
    /// Always has an end.
    public let span: TimeSpan
    public let text: String
    /// Speakers are numbered from 1; `nil` when speakers were not told apart.
    public let speaker: Int?

    /// Rounds both times to the millisecond; the segment starts at or after zero and ends after it starts.
    public init(start: Duration, end: Duration, text: String, speaker: Int? = nil) throws {
      span = try TimeSpan(start: start, end: end)
      if let speaker, speaker < 1 { throw ModelError("speakers are numbered from 1") }
      self.text = try text.requiringText("segment text")
      self.speaker = speaker
    }

    public var start: Duration { span.start }
    public var end: Duration { span.end ?? span.start }
  }
}

extension Transcript: Codable {
  private enum CodingKeys: String, CodingKey {
    case language, origin, model, segments
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let origin: Origin =
      switch try container.decode(String.self, forKey: .origin) {
      case "platform": .platform
      case "recognized": .recognized(try container.decode(SpeechModel.self, forKey: .model))
      case let other:
        throw DecodingError.dataCorruptedError(
          forKey: .origin, in: container, debugDescription: "unknown origin \(other)")
      }
    let language = try container.decodeIfPresent(String.self, forKey: .language)
    let segments = try container.decode([Segment].self, forKey: .segments)
    self = try decoder.validated { try Transcript(language: language, origin: origin, segments: segments) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(language, forKey: .language)
    switch origin {
    case .platform:
      try container.encode("platform", forKey: .origin)
    case .recognized(let model):
      try container.encode("recognized", forKey: .origin)
      try container.encode(model, forKey: .model)
    }
    try container.encode(segments, forKey: .segments)
  }
}

extension Transcript.Segment: Codable {
  private enum CodingKeys: String, CodingKey {
    case start, end, text, speaker
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let start = Seconds.duration(try container.decode(Double.self, forKey: .start))
    let end = Seconds.duration(try container.decode(Double.self, forKey: .end))
    let text = try container.decode(String.self, forKey: .text)
    let speaker = try container.decodeIfPresent(Int.self, forKey: .speaker)
    self = try decoder.validated { try Transcript.Segment(start: start, end: end, text: text, speaker: speaker) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Seconds.number(start), forKey: .start)
    try container.encode(Seconds.number(end), forKey: .end)
    try container.encode(text, forKey: .text)
    try container.encodeIfPresent(speaker, forKey: .speaker)
  }
}
