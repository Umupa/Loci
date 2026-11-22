import FluidAudio
import Foundation
import LociModel

public protocol Diarizing: Sendable {
  func speakers(in audio: URL, models: URL, progress: @escaping @Sendable (Fraction) -> Void) async throws
    -> [SpeakerTurn]
}

public struct FluidDiarizer: Diarizing {
  public init() {}

  public func speakers(in audio: URL, models: URL, progress: @escaping @Sendable (Fraction) -> Void) async throws
    -> [SpeakerTurn]
  {
    let manager = OfflineDiarizerManager()
    let models = try await OfflineDiarizerModels.load(from: models) { update in
      if case .downloading = update.phase { progress(Fraction(update.fractionCompleted * 0.2)) }
    }
    try Task.checkCancellation()
    manager.initialize(models: models)
    progress(Fraction(0.2))
    let diarization = try await manager.process(audio) { processed, total in
      if total > 0 { progress(Fraction(0.2 + 0.75 * Double(processed) / Double(total))) }
    }
    try Task.checkCancellation()
    return diarization.segments.compactMap { segment in
      let start = Double(segment.startTimeSeconds)
      let end = Double(segment.endTimeSeconds)
      guard start.isFinite, end.isFinite else { return nil }
      return try? SpeakerTurn(speaker: segment.speakerId, start: .seconds(max(0, start)), end: .seconds(end))
    }
  }
}

public struct SpeakerTurn: Sendable {
  public let speaker: String
  public let span: TimeSpan

  public init(speaker: String, start: Duration, end: Duration) throws {
    self.speaker = speaker
    span = try TimeSpan(start: start, end: end)
  }

  private var start: Duration { span.start }
  private var end: Duration { span.end ?? span.start }

  public static func label(_ transcript: Transcript, from turns: [SpeakerTurn]) throws -> Transcript {
    let turns = turns.sorted { ($0.start, $0.speaker, $0.end) < ($1.start, $1.speaker, $1.end) }
    var first = turns.startIndex
    var numbers: [String: Int] = [:]
    let segments = try transcript.segments.map { segment in
      while first < turns.endIndex, turns[first].end <= segment.start { first += 1 }
      var overlap: [String: Duration] = [:]
      var speakers: [String] = []
      for turn in turns[first...].prefix(while: { $0.start < segment.end }) {
        let shared = min(segment.end, turn.end) - max(segment.start, turn.start)
        guard shared > .zero else { continue }
        if overlap[turn.speaker] == nil { speakers.append(turn.speaker) }
        overlap[turn.speaker, default: .zero] += shared
      }
      guard let speaker = speakers.max(by: { overlap[$0, default: .zero] < overlap[$1, default: .zero] })
      else { return segment }
      let number = numbers[speaker] ?? numbers.count + 1
      numbers[speaker] = number
      return try Transcript.Segment(start: segment.start, end: segment.end, text: segment.text, speaker: number)
    }
    return try Transcript(language: transcript.language, origin: transcript.origin, segments: segments)
  }
}
