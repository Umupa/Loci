/// Where the work of making one item readable stands. Each stage leaves a file behind, so a job stopped
/// part way picks up after the last finished stage.
public struct Job: Hashable, Codable, Sendable {
  public let item: EntityID
  public let stage: Stage
  public let state: State

  public init(item: EntityID, stage: Stage, state: State) {
    self.item = item
    self.stage = stage
    self.state = state
  }

  /// In the order they run. Articles stop after `extract`; video and audio skip it.
  public enum Stage: String, CaseIterable, Codable, Hashable, Sendable {
    /// Reads the title, cover, duration and subtitles behind a link.
    case resolve
    /// Takes the text out of a web page.
    case extract
    case download
    case transcribe
    case translate
    /// Finds chapters and highlights.
    case outline
  }

  public enum State: Hashable, Codable, Sendable {
    case queued
    /// `nil` when how far along cannot be told.
    case running(progress: Fraction?)
    /// Carries on by itself once the need is met.
    case waiting(Need)
    case failed(Failure)
    case done
  }

  public enum Need: Hashable, Codable, Sendable {
    case component(Component)
    case speechModel(SpeechModel)
    /// The site wants a signed-in visitor; sign in from the built-in browser.
    case login(site: String)
    /// No agent CLI is available to translate or outline.
    case agent
  }

  public struct Failure: Hashable, Codable, Sendable {
    /// What went wrong, in the words of the program or site that said so.
    public let reason: String
    /// What the reader can do about it, when there is something.
    public let remedy: Remedy?

    public init(reason: String, remedy: Remedy? = nil) {
      self.reason = reason
      self.remedy = remedy
    }
  }

  public enum Remedy: Hashable, Codable, Sendable {
    case updateComponent(Component)
    case retry
    case chooseBrowserLogin
  }
}

/// A share of something, from 0 to 1.
public struct Fraction: Hashable, Comparable, Codable, Sendable {
  public let value: Double

  /// Clamps `value` into 0...1; anything that is not a number counts as 0.
  public init(_ value: Double) {
    self.value = value.isNaN ? 0 : min(max(value, 0), 1)
  }

  public init(from decoder: any Decoder) throws {
    self.init(try decoder.singleValueContainer().decode(Double.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }

  public static func < (lhs: Fraction, rhs: Fraction) -> Bool {
    lhs.value < rhs.value
  }
}
