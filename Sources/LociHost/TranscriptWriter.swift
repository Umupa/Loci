import Foundation
import LociAgents
import LociModel
import LociStore

/// The app's `TranscriptAgent`: one-off turns on the default agent, belonging to no mentor, each in an
/// empty folder so the agent sees only what it is sent. The transcript goes in pieces; each answer is JSON
/// whose shape is checked, and a piece whose answer does not fit is asked once more before giving up.
public struct AgentTranscriptAgent: TranscriptAgent {
  private let choice: AgentChoice
  private let agents: @Sendable (Mentor.Provider) async -> (any AgentDriver)?
  private let folder: @Sendable () throws -> ScratchFolder
  private let translationPiece: Int
  private let outlinePiece: Int

  /// `translationPiece` and `outlinePiece` are how many segments go in one turn.
  public init(
    choice: AgentChoice, agents: @escaping @Sendable (Mentor.Provider) async -> (any AgentDriver)?,
    folder: @escaping @Sendable () throws -> ScratchFolder = { try ScratchFolder() }, translationPiece: Int = 60,
    outlinePiece: Int = 200
  ) {
    self.choice = choice
    self.agents = agents
    self.folder = folder
    self.translationPiece = max(1, translationPiece)
    self.outlinePiece = max(1, outlinePiece)
  }

  public func translate(_ transcript: Transcript, into language: String) async throws(HostError) -> Translation {
    var lines: [String] = []
    let pieces = Self.pieces(of: transcript.segments, size: translationPiece)
    for (number, piece) in pieces.enumerated() {
      let prompt = TranscriptPrompts.translation(of: piece.map(\.text), into: language)
      lines += try await answer(prompt, piece: number + 1, of: pieces.count) { reply throws(TranscriptAnswerError) in
        try TranscriptAnswers.lines(in: reply, count: piece.count)
      }
    }
    return try attempt { try Translation(language: language, lines: lines) }
  }

  public func outline(_ transcript: Transcript, title: String) async throws(HostError) -> Outline {
    let duration = transcript.segments.last?.end ?? .zero
    var chapters: [Outline.Chapter] = []
    var highlights: [Outline.Highlight] = []
    let pieces = Self.pieces(of: transcript.segments, size: outlinePiece)
    for (number, piece) in pieces.enumerated() {
      let prompt = TranscriptPrompts.outline(of: piece, title: title, piece: number + 1, of: pieces.count)
      let found = try await answer(prompt, piece: number + 1, of: pieces.count) {
        reply throws(TranscriptAnswerError) in
        try TranscriptAnswers.outline(
          in: reply, from: piece.first?.start ?? .zero, to: piece.last?.end ?? .zero,
          duration: duration)
      }
      for chapter in found.chapters where chapter.title != chapters.last?.title { chapters.append(chapter) }
      highlights += found.highlights
    }
    return try attempt { try Outline(chapters: chapters, highlights: highlights) }
  }

  static func pieces(of segments: [Transcript.Segment], size: Int) -> [[Transcript.Segment]] {
    stride(from: 0, to: segments.count, by: size).map { Array(segments[$0..<min($0 + size, segments.count)]) }
  }

  /// Asks for one piece, and once more when the answer does not fit.
  private func answer<Value>(
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
    guard let driver = await agents(choice.provider) else {
      throw .invalidRequest("\(choice.provider.rawValue) is not installed on this Mac.")
    }
    let scratch = try attempt { try folder() }
    defer { scratch.remove() }
    do throws(AgentError) {
      let session = try await driver.open(
        SessionConfiguration(workingDirectory: scratch.url, model: choice.model, effort: choice.effort))
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
