/// Where the work of making one item readable stands. Each stage leaves a file behind, so a job paused
/// part way picks up after the last finished stage.
public struct Job: Hashable, Codable, Sendable {
  public let item: EntityID
  public let stage: Stage
  public let state: State
  /// Every stage the item goes through, in order, `stage` among them; empty when the host did not say.
  public let stages: [Stage]

  public init(item: EntityID, stage: Stage, state: State, stages: [Stage] = []) {
    self.item = item
    self.stage = stage
    self.state = state
    self.stages = stages
  }

  private enum CodingKeys: String, CodingKey {
    case item, stage, state, stages
  }

  /// A job from a Mac that did not send its stages has none.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      item: try container.decode(EntityID.self, forKey: .item), stage: try container.decode(Stage.self, forKey: .stage),
      state: try container.decode(State.self, forKey: .state),
      stages: try container.decodeIfPresent([Stage].self, forKey: .stages) ?? [])
  }

  /// The same job in another state.
  public func with(_ state: State) -> Job {
    Job(item: item, stage: stage, state: state, stages: stages)
  }

  /// In the order they run.
  public enum Stage: String, CaseIterable, Codable, Hashable, Sendable {
    /// Reads the title, cover, duration and subtitles behind a link.
    case resolve
    case fetchPage
    /// Takes the text out of a web page.
    case extract
    case findCover
    case download
    case transcribe
    case diarize
    case translate
    /// Finds chapters; key points are picked when the reader asks.
    case outline
    /// Tidies an article's text, only when the reader asks.
    case tidy
  }

  public enum State: Hashable, Codable, Sendable {
    case queued
    /// `nil` when how far along cannot be told; `amount` only for work measured in bytes.
    case running(progress: Fraction?, amount: Amount? = nil)
    /// Carries on by itself once the need is met.
    case waiting(Need)
    case failed(Failure)
    /// Paused by the reader; what was made so far is kept, and it carries on from there when resumed, also
    /// after the app quits. `progress` is how far the stage had got when it was paused.
    case paused(progress: Fraction?)
    case done
  }

  /// How many bytes of a download have arrived, of how many.
  public struct Amount: Hashable, Codable, Sendable {
    public let done: Int64
    /// `nil` while the size is not known.
    public let total: Int64?

    public init(done: Int64, total: Int64?) {
      self.done = done
      self.total = total
    }
  }

  public enum Need: Hashable, Codable, Sendable {
    case component(Component)
    case speechModel(SpeechModel)
    /// The site wants a signed-in visitor; sign in from the built-in browser.
    case login(site: String)
    /// No model is configured to translate or find chapters with.
    case modelService

    private enum CodingKeys: String, CodingKey {
      case component, speechModel, login
      case modelService = "agent"
    }
  }

  public struct Failure: Hashable, Codable, Sendable {
    /// What went wrong, in the words of the program or site that said so.
    public let reason: String
    /// What the reader can do about it, when there is something.
    public let remedy: Remedy?
    /// What kind of trouble it was, when it could be told; the reader is told this rather than the reason.
    public let cause: Cause?

    public init(reason: String, remedy: Remedy? = nil, cause: Cause? = nil) {
      self.reason = reason
      self.remedy = remedy
      self.cause = cause
    }
  }

  public enum Remedy: Hashable, Codable, Sendable {
    case updateComponent(Component)
    case retry
    case chooseBrowserLogin
    /// Nothing in Loci will help; the original page may say why.
    case openSource
  }

  /// The kinds of trouble a fetch runs into that the reader can be told about in their own language.
  public enum Cause: String, Hashable, Codable, Sendable {
    /// Removed, private, or not offered where the reader is.
    case unavailable
    /// The site could not be reached.
    case network
    /// A component no longer understands the site.
    case outdated
    /// The browser's sign-in could not be read.
    case cookiesUnreadable
    case noArticleText
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
