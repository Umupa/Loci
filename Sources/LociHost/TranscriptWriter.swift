import Foundation
import LociAgents
import LociModel
import LociStore

/// The app's `TranscriptAgent`: one-off turns on Loci's runtime, without Loci's soul or memory, each in an
/// empty folder so the agent sees only what it is sent. Each answer is JSON whose shape is checked, and an
/// answer that does not fit is asked for once more before giving up.
public struct AgentTranscriptAgent: TranscriptAgent {
  private let runtime: Runtime
  private let agents: @Sendable (Provider) async -> (any AgentDriver)?
  private let folder: @Sendable () throws -> ScratchFolder
  let outlinePiece: Int
  let passagePiece: Int

  /// `outlinePiece` is how many segments go in one turn of outlining, `passagePiece` how many passages of an
  /// article in one turn of picking key points.
  public init(
    runtime: Runtime, agents: @escaping @Sendable (Provider) async -> (any AgentDriver)?,
    folder: @escaping @Sendable () throws -> ScratchFolder = { try ScratchFolder() }, outlinePiece: Int = 200,
    passagePiece: Int = 150
  ) {
    self.runtime = runtime
    self.agents = agents
    self.folder = folder
    self.outlinePiece = max(1, outlinePiece)
    self.passagePiece = max(1, passagePiece)
  }

  public func translate(lines: [String], into language: String) async throws(HostError) -> [String] {
    try await answer(TranscriptPrompts.translation(of: lines, into: language), piece: 1, of: 1) {
      reply throws(TranscriptAnswerError) in
      try TranscriptAnswers.lines(in: reply, count: lines.count)
    }
  }

  public func outline(_ transcript: Transcript, title: String) async throws(HostError) -> Outline {
    var chapters: [Outline.Chapter] = []
    let pieces = Self.pieces(of: transcript.segments, size: outlinePiece)
    for (number, piece) in pieces.enumerated() {
      let prompt = TranscriptPrompts.outline(of: piece, title: title, piece: number + 1, of: pieces.count)
      let found = try await answer(prompt, piece: number + 1, of: pieces.count) {
        reply throws(TranscriptAnswerError) in
        try TranscriptAnswers.outline(in: reply, from: piece.first?.start ?? .zero, to: piece.last?.end ?? .zero)
      }
      for chapter in found.chapters where chapter.title != chapters.last?.title { chapters.append(chapter) }
    }
    return try attempt { try Outline(chapters: chapters) }
  }

  public func translate(passages: [String], into language: String) async throws(HostError) -> [String] {
    try await answer(TranscriptPrompts.translation(ofPassages: passages, into: language), piece: 1, of: 1) {
      reply throws(TranscriptAnswerError) in
      try TranscriptAnswers.lines(in: reply, count: passages.count)
    }
  }

  static func pieces(of segments: [Transcript.Segment], size: Int) -> [[Transcript.Segment]] {
    stride(from: 0, to: segments.count, by: size).map { Array(segments[$0..<min($0 + size, segments.count)]) }
  }

  /// Asks for one piece, and once more when the answer does not fit.
  func answer<Value>(
    _ prompt: String, piece: Int, of pieces: Int, reading: (String) throws(TranscriptAnswerError) -> Value
  ) async throws(HostError) -> Value {
    var problem = ""
    for _ in 0..<2 {
      let reply = try await ask(prompt)
      do throws(TranscriptAnswerError) {
        return try reading(reply)
      } catch {
        problem = error.reason
      }
    }
    let place = pieces > 1 ? " (part \(piece) of \(pieces))" : ""
    throw .invalidRequest("The agent's answer\(place) could not be used: \(problem)")
  }

  /// An agent that cannot answer at all is not asked again.
  private func ask(_ prompt: String) async throws(HostError) -> String {
    guard let driver = await agents(runtime.provider) else {
      throw .invalidRequest("\(runtime.provider.rawValue) is not installed on this Mac.")
    }
    let scratch = try attempt { try folder() }
    defer { scratch.remove() }
    do throws(AgentError) {
      let session = try await driver.open(
        SessionConfiguration(workingDirectory: scratch.url, model: runtime.model, effort: runtime.effort))
      defer { Task { await session.close() } }
      var reply = ""
      for await event in try await session.send(prompt).events {
        switch event {
        case .text(let more): reply += more
        case .ended(.failed(let error)): throw error
        default: continue
        }
      }
      return reply
    } catch {
      throw .invalidRequest(error.explanation)
    }
  }
}
