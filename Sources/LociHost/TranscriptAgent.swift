import LociModel

/// Writes what an agent adds to a transcript or an article: a translation and an outline. The app's version runs
/// a one-off turn on a local agent CLI, without Loci's soul or memory.
public protocol TranscriptAgent: Sendable {
  /// One line per segment, in order; the result fits `transcript`.
  func translate(_ transcript: Transcript, into language: String) async throws(HostError) -> Translation
  func outline(_ transcript: Transcript, title: String) async throws(HostError) -> Outline
  /// One translation per passage of an article, in order, each still Markdown.
  func translate(passages: [String], into language: String) async throws(HostError) -> [String]
}
