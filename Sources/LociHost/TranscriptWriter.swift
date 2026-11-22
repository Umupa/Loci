import Foundation
import LociAgents
import LociModel
import LociStore

/// The app's `TranscriptAgent`: one-off turns on Loci's runtime, without Loci's soul or memory, each in an
/// empty folder so the agent sees only what it is sent. Each answer is JSON whose shape is checked, and an
/// answer that does not fit is asked for once more before giving up.
public struct AgentTranscriptAgent: RuntimeTranscriptAgent {
  private let runtime: Runtime
  private let agents: @Sendable (Provider) async -> (any AgentDriver)?
  private let folder: @Sendable () throws -> ScratchFolder
  private let outlinePiece: Int
  private let passagePiece: Int

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

  private var writing: TranscriptWriting {
    TranscriptWriting(outlinePiece: outlinePiece, passagePiece: passagePiece, parallelism: 1, ask: ask)
  }

  public func translate(lines: [String], into language: String) async throws(HostError) -> [String] {
    try await writing.translate(lines: lines, into: language)
  }

  public func translate(passages: [String], into language: String) async throws(HostError) -> [String] {
    try await writing.translate(passages: passages, into: language)
  }

  public func translate(_ input: [String], using prompt: TranslationPrompt) async throws(HostError) -> [String] {
    try await writing.translate(input, using: prompt)
  }

  public func outline(_ transcript: Transcript, title: String) async throws(HostError) -> Outline {
    try await writing.outline(transcript, title: title)
  }

  public func keyPoints(of source: KeyPointSource, count: KeyPointCount, for reader: KeyPointReader)
    async throws(HostError) -> [KeyPoint]
  {
    try await writing.keyPoints(of: source, count: count, for: reader)
  }

  /// An agent that cannot answer at all is not asked again.
  func ask(_ prompt: String) async throws(HostError) -> String {
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
