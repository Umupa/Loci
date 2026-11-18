import Foundation
import LociModel
import Testing

@testable import LociMedia

struct SubtitlesTests {
  @Test func eachCueBecomesASegmentWithoutMarkup() throws {
    let vtt = """
      WEBVTT
      Kind: captions
      Language: en

      00:00:01.000 --> 00:00:04.500 align:start position:0%
      All right, so here we are <c>in front of</c> the elephants

      1
      00:04.500 --> 00:07.250
      the cool thing &amp; these guys
      """

    let segments = Subtitles.segments(fromWebVTT: vtt)

    #expect(
      segments.map(\.text) == ["All right, so here we are in front of the elephants", "the cool thing & these guys"])
    #expect(segments.map(\.start) == [.seconds(1), .milliseconds(4500)])
    #expect(segments.last?.end == .milliseconds(7250))
  }

  @Test func aRollingCaptionKeepsEachLineOnce() {
    let vtt = """
      WEBVTT

      00:00:00.000 --> 00:00:02.000
      first line

      00:00:02.000 --> 00:00:04.000
      first line
      second line

      00:00:04.000 --> 00:00:06.000
      second line
      third line
      """

    #expect(Subtitles.segments(fromWebVTT: vtt).map(\.text) == ["first line", "second line", "third line"])
  }

  @Test func cuesWithoutTextOrTimeAreSkipped() {
    let vtt = "WEBVTT\n\nNOTE hello\n\n00:00:01,000 --> 00:00:02,000\n\n\n00:00:03,000 --> 00:00:04,000\nsrt style\n"

    let segments = Subtitles.segments(fromWebVTT: vtt)

    #expect(segments.map(\.text) == ["srt style"])
    #expect(segments.first?.start == .seconds(3))
  }
}
