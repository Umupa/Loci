import LociModel

extension TranscriptWriting {
  func keyPoints(of source: KeyPointSource, count: KeyPointCount, for reader: KeyPointReader)
    async throws(HostError) -> [KeyPoint]
  {
    let (units, title, size): (KeyPointUnits, String, Int) =
      switch source {
      case .transcript(let transcript, let title): (.sentences(transcript.segments), title, outlinePiece)
      case .article(let passages, let title): (.passages(passages), title, passagePiece)
      }
    guard units.count > 0 else { throw .invalidRequest("There is nothing to pick key points from.") }
    let wanted = min(count.range.lowerBound, units.count)...min(count.range.upperBound, units.count)
    let pieces = stride(from: 0, to: units.count, by: size).map { $0..<min($0 + size, units.count) }
    guard pieces.count > 1 else {
      let prompt = KeyPointPrompts.pick(
        units.lines(0..<units.count), of: units, title: title, count: wanted, for: reader)
      return try await answer(prompt, piece: 1, of: 1) { reply throws(TranscriptAnswerError) in
        try KeyPointAnswers.points(in: reply, of: units, within: 0..<units.count, count: wanted)
      }
    }
    var candidates: [KeyPoint] = []
    let pick = { @Sendable (number: Int, piece: Range<Int>) async throws(HostError) -> [KeyPoint] in
      let suggest = 0...wanted.upperBound
      let prompt = KeyPointPrompts.pick(
        units.lines(piece), of: units, title: title, count: suggest, for: reader, piece: (number + 1, pieces.count))
      return try await answer(prompt, piece: number + 1, of: pieces.count) {
        reply throws(TranscriptAnswerError) in
        try KeyPointAnswers.points(in: reply, of: units, within: piece, count: suggest)
      }
    }
    try await Batches.run(pieces, parallelism: parallelism, work: pick) { (found: [KeyPoint]) async throws(HostError) in
      candidates += found
    }
    guard !candidates.isEmpty else { throw .invalidRequest("The agent found nothing worth picking.") }
    let final = min(wanted.lowerBound, candidates.count)...min(wanted.upperBound, candidates.count)
    let prompt = KeyPointPrompts.choose(among: candidates, of: units, title: title, count: final, for: reader)
    return try await answer(prompt, piece: 1, of: 1) { reply throws(TranscriptAnswerError) in
      try KeyPointAnswers.points(in: reply, of: units, within: 0..<units.count, count: final, among: candidates)
    }
  }
}
