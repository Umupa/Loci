import LociModel

struct TranscriptWriting: TranscriptAgent {
  var outlinePiece = 200
  var passagePiece = 150
  let parallelism: Int
  var author = "agent"
  let ask: @Sendable (String) async throws(HostError) -> String

  func translate(lines: [String], into language: String) async throws(HostError) -> [String] {
    try await translate(
      lines,
      using: TranslationPrompt(
        kind: .transcript, language: language, instructions: TranslationSettings.defaultTranscriptPrompt))
  }

  func translate(passages: [String], into language: String) async throws(HostError) -> [String] {
    try await translate(
      passages,
      using: TranslationPrompt(
        kind: .article, language: language, instructions: TranslationSettings.defaultArticlePrompt))
  }

  func translate(_ input: [String], using prompt: TranslationPrompt) async throws(HostError) -> [String] {
    try await answer(prompt.request(for: input), piece: 1, of: 1) { reply throws(TranscriptAnswerError) in
      try TranscriptAnswers.lines(in: reply, count: input.count)
    }
  }

  func tidy(_ piece: String, title: String) async throws(HostError) -> String {
    try await answer(TidyPrompt.request(for: piece, title: title), piece: 1, of: 1) {
      reply throws(TranscriptAnswerError) in
      try TidyPrompt.markdown(in: reply)
    }
  }

  func outline(_ transcript: Transcript, title: String) async throws(HostError) -> Outline {
    var chapters: [Outline.Chapter] = []
    let pieces = Batches.pieces(of: transcript.segments, size: outlinePiece)
    let write = { @Sendable (number: Int, piece: [Transcript.Segment]) async throws(HostError) -> Outline in
      let prompt = TranscriptPrompts.outline(of: piece, title: title, piece: number + 1, of: pieces.count)
      return try await answer(prompt, piece: number + 1, of: pieces.count) { reply throws(TranscriptAnswerError) in
        try TranscriptAnswers.outline(in: reply, from: piece.first?.start ?? .zero, to: piece.last?.end ?? .zero)
      }
    }
    try await Batches.run(pieces, parallelism: parallelism, work: write) { (found: Outline) async throws(HostError) in
      for chapter in found.chapters where chapter.title != chapters.last?.title { chapters.append(chapter) }
    }
    return try attempt { try Outline(chapters: chapters) }
  }

  func answer<Value>(
    _ prompt: String, piece: Int, of pieces: Int, reading: (String) throws(TranscriptAnswerError) -> Value
  ) async throws(HostError) -> Value {
    var problem = ""
    for _ in 0..<2 {
      if Task.isCancelled { throw .invalidRequest("The request was cancelled.") }
      let reply = try await ask(prompt)
      do throws(TranscriptAnswerError) {
        return try reading(reply)
      } catch {
        problem = error.reason
      }
    }
    let place = pieces > 1 ? " (part \(piece) of \(pieces))" : ""
    throw .invalidRequest("The \(author)'s answer\(place) could not be used: \(problem)")
  }
}
