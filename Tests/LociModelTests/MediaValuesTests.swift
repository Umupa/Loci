import Foundation
import Testing

@testable import LociModel

struct MediaValuesTests {
  @Test func aTranscriptSurvivesItsFile() throws {
    let transcript = try Transcript(
      language: "en", origin: .recognized(.largeV3TurboQuantized),
      segments: [
        Transcript.Segment(start: .milliseconds(1_200), end: .milliseconds(3_400), text: "Hello.", speaker: 1),
        Transcript.Segment(start: .milliseconds(3_400), end: .milliseconds(5_000), text: "Welcome."),
      ])

    #expect(try Fixture.roundTrip(transcript) == transcript)
  }

  @Test func readsSegmentTimesInSeconds() throws {
    let transcript = try Fixture.decode(
      Transcript.self, #"{"origin":"platform","segments":[{"start":12.04,"end":14.5,"text":"Hi"}]}"#)

    #expect(transcript.segments[0].start == .milliseconds(12_040))
    #expect(transcript.segments[0].end == .milliseconds(14_500))
    #expect(transcript.segments[0].speaker == nil)
  }

  static let brokenSegments = [
    #"{"start":3,"end":3,"text":"x"}"#,
    #"{"start":-1,"end":3,"text":"x"}"#,
    #"{"start":1,"end":3,"text":" "}"#,
    #"{"start":1,"end":3,"text":"x","speaker":0}"#,
  ]

  @Test(arguments: brokenSegments)
  func aSegmentThatCannotBeSpokenIsRejected(json: String) {
    #expect(throws: DecodingError.self) { try Fixture.decode(Transcript.Segment.self, json) }
  }

  @Test func segmentsAreInTimeOrder() throws {
    #expect(throws: ModelError.self) {
      try Transcript(
        language: nil, origin: .platform,
        segments: [
          Transcript.Segment(start: .seconds(5), end: .seconds(6), text: "b"),
          Transcript.Segment(start: .seconds(1), end: .seconds(2), text: "a"),
        ])
    }
  }

  @Test func aSegmentKnowsItsTimeSpan() throws {
    let segment = try Transcript.Segment(start: .seconds(204.1), end: .seconds(207.8), text: "x")

    #expect(segment.span == (try TimeSpan(start: .seconds(204.1), end: .seconds(207.8))))
  }

  @Test func aTranslationHasOneLinePerSegment() throws {
    let transcript = try Transcript(
      language: "en", origin: .platform,
      segments: [Transcript.Segment(start: .seconds(0), end: .seconds(1), text: "Hi")])
    let fitting = try Translation(language: "zh-Hans", lines: ["你好"])
    let short = try Translation(language: "zh-Hans", lines: [])

    #expect(fitting.fits(transcript))
    #expect(!short.fits(transcript))
    #expect(try Fixture.roundTrip(fitting) == fitting)
  }

  @Test func anOutlineSurvivesItsFile() throws {
    let outline = try Outline(
      chapters: [Outline.Chapter(start: .zero, title: "Intro"), Outline.Chapter(start: .seconds(90), title: "Scores")],
      highlights: [
        Outline.Highlight(span: try TimeSpan(start: .seconds(95), end: .seconds(130)), title: "Why", reason: "Core")
      ])

    #expect(try Fixture.roundTrip(outline) == outline)
  }

  @Test func chaptersAreInTimeOrder() {
    #expect(throws: ModelError.self) {
      try Outline(
        chapters: [Outline.Chapter(start: .seconds(9), title: "b"), Outline.Chapter(start: .seconds(1), title: "a")],
        highlights: [])
    }
  }

  @Test func aHighlightCoversAStretchOfTime() {
    #expect(throws: ModelError.self) {
      try Outline.Highlight(span: try TimeSpan(start: .seconds(1)), title: "x", reason: "y")
    }
  }

  @Test func theRecommendedSpeechModelIsTheDefault() {
    #expect(SpeechModel.recommended == .largeV3TurboQuantized)
    #expect(SpeechModel.allCases.count == 7)
    #expect(SpeechModel.allCases.allSatisfy { (1...5).contains($0.speed) && (1...5).contains($0.accuracy) })
  }

  @Test func everyJobStateSurvivesJSON() throws {
    let states: [Job.State] = [
      .queued, .running(progress: nil), .running(progress: Fraction(0.42)), .waiting(.component(.ytDlp)),
      .waiting(.speechModel(.base)), .waiting(.login(site: "bilibili.com")), .waiting(.agent),
      .failed(Job.Failure(reason: "HTTP 403", remedy: .updateComponent(.ytDlp))), .failed(Job.Failure(reason: "x")),
      .done,
    ]
    for state in states {
      let job = Job(item: Fixture.item, stage: .transcribe, state: state)

      #expect(try HostCodingTests.roundTrips(job))
    }
  }

  @Test func progressStaysBetweenZeroAndOne() {
    #expect(Fraction(1.7) == Fraction(1))
    #expect(Fraction(-2).value == 0)
    #expect(Fraction(.nan).value == 0)
  }

  @Test func componentStatusSurvivesJSON() throws {
    let statuses = [
      ComponentStatus(
        component: .ytDlp, installation: .system(path: "/opt/homebrew/bin/yt-dlp", version: "2026.10.26")),
      ComponentStatus(component: .ffmpeg, installation: .managed(version: "9.0.2")),
      ComponentStatus(component: .quickJS, installation: .missing),
    ]

    #expect(try HostCodingTests.roundTrips(statuses))
  }

  @Test func anItemKeepsWhereAndWhenItWasPublished() throws {
    let item = try Item(
      id: Fixture.item, kind: .video(duration: .seconds(600)), title: "Talk", site: "YouTube · KubeCon",
      published: Fixture.instant)

    #expect(try Fixture.roundTrip(item) == item)
    #expect(throws: ModelError.self) { try Item(id: Fixture.item, kind: .article, title: "x", site: " ") }
  }
}
