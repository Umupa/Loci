import LociMedia
import LociModel
import Testing

struct DiarizationTests {
  @Test func sentencesUseTheSpeakerWithTheMostTotalOverlap() throws {
    let transcript = try Transcript(
      language: "en", origin: .platform,
      segments: [
        try .init(start: .zero, end: .seconds(5), text: "First."),
        try .init(start: .seconds(5), end: .seconds(7), text: "Second."),
        try .init(start: .seconds(7), end: .seconds(8), text: "No match."),
        try .init(start: .seconds(8), end: .seconds(9), text: "First again."),
      ])
    let turns = [
      try SpeakerTurn(speaker: "Z", start: .seconds(8), end: .seconds(9)),
      try SpeakerTurn(speaker: "Z", start: .zero, end: .seconds(1.5)),
      try SpeakerTurn(speaker: "A", start: .seconds(1.5), end: .seconds(3.5)),
      try SpeakerTurn(speaker: "Z", start: .seconds(3.5), end: .seconds(5)),
      try SpeakerTurn(speaker: "A", start: .seconds(5), end: .seconds(7)),
    ]

    let labeled = try SpeakerTurn.label(transcript, from: turns)

    #expect(labeled.segments.map(\.speaker) == [1, 2, nil, 1])
    #expect(labeled.segments.map(\.span) == transcript.segments.map(\.span))
    #expect(labeled.segments.map(\.text) == transcript.segments.map(\.text))
    #expect(labeled.origin == transcript.origin)
    #expect(labeled.language == transcript.language)
  }
}
