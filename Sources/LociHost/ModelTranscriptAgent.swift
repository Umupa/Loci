import LociMedia
import LociModel

struct ModelTranscriptAgent: TranscriptAgent {
  let service: ModelService
  private let writing: TranscriptWriting

  init(service: ModelService, key: String, client: ModelClient, gate: Gate, parallelism: Int) {
    self.service = service
    writing = TranscriptWriting(parallelism: parallelism, author: "model") { prompt async throws(HostError) in
      try await gate.through { () async throws(HostError) in
        guard !Task.isCancelled else { throw .invalidRequest("The request was cancelled.") }
        do throws(FetchError) {
          return try await client.answer(prompt, using: service, key: key)
        } catch {
          throw .invalidRequest(error.reason)
        }
      }
    }
  }

  func translate(lines: [String], into language: String) async throws(HostError) -> [String] {
    try await writing.translate(lines: lines, into: language)
  }

  func translate(passages: [String], into language: String) async throws(HostError) -> [String] {
    try await writing.translate(passages: passages, into: language)
  }

  func translate(_ input: [String], using prompt: TranslationPrompt) async throws(HostError) -> [String] {
    try await writing.translate(input, using: prompt)
  }

  func outline(_ transcript: Transcript, title: String) async throws(HostError) -> Outline {
    try await writing.outline(transcript, title: title)
  }

  func keyPoints(of source: KeyPointSource, count: KeyPointCount, for reader: KeyPointReader)
    async throws(HostError) -> [KeyPoint]
  {
    try await writing.keyPoints(of: source, count: count, for: reader)
  }
}
