import LociModel

/// Writes what an agent adds to a transcript: a translation and an outline. The app's version runs a
/// one-off turn on a local agent CLI that belongs to no mentor.
public protocol TranscriptAgent: Sendable {
  /// One line per segment, in order; the result fits `transcript`.
  func translate(_ transcript: Transcript, into language: String) async throws(HostError) -> Translation
  func outline(_ transcript: Transcript, title: String) async throws(HostError) -> Outline
}
