import LociModel

/// Writes what an agent adds to a transcript or an article: a translation, chapters and key points. The app's
/// version runs a one-off turn on a local agent CLI, without Loci's soul or memory.
public protocol TranscriptAgent: Sendable {
  /// One translated line for each of `lines`, in order. A transcript goes a batch of lines at a time.
  func translate(lines: [String], into language: String) async throws(HostError) -> [String]
  /// Chapters only; key points are picked when the reader asks.
  func outline(_ transcript: Transcript, title: String) async throws(HostError) -> Outline
  /// One translation per passage of an article, in order, each still Markdown.
  func translate(passages: [String], into language: String) async throws(HostError) -> [String]
  /// Within `count.range`, or as many as there are sentences or passages when there are fewer; in order.
  func keyPoints(of source: KeyPointSource, count: KeyPointCount, for reader: KeyPointReader)
    async throws(HostError) -> [KeyPoint]
}

/// What key points are picked from.
public enum KeyPointSource: Sendable {
  case transcript(Transcript, title: String)
  /// The article's passages as `ArticlePassages` cuts them, in order.
  case article(passages: [String], title: String)
}

/// Who the key points are picked for, so the reasons speak to them.
public struct KeyPointReader: Sendable {
  /// The BCP 47 tag titles and reasons are written in.
  public let language: String
  /// `USER.md`: what they do and why they learn.
  public let profile: String
  /// What they wrote on taking the item in, when they wrote anything.
  public let why: String?

  public init(language: String, profile: String, why: String?) {
    self.language = language
    self.profile = profile
    self.why = why
  }
}
