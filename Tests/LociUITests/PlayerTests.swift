import Foundation
import LociModel
import Testing

@testable import LociUI

@Suite struct PlayerTests {
  /// An 840-point window with the sidebar open leaves about 590 for the page: the transcript panel folds away
  /// rather than squeezing the video under the sidebar, and opens over the video when asked for.
  @Test func aNarrowPageFoldsThePanelAndOpensItOverTheVideo() {
    #expect(!MediaLayout(width: 588, panelShown: true, panelOver: false).besideStage)
    #expect(MediaLayout(width: 588, panelShown: true, panelOver: true).overStage)
    #expect(MediaLayout(width: 1028, panelShown: true, panelOver: false).besideStage)
    #expect(!MediaLayout(width: 1028, panelShown: true, panelOver: true).overStage)
    #expect(!MediaLayout(width: 1028, panelShown: false, panelOver: false).besideStage)
  }

  /// A video kept as audio only keeps its cover up instead of a black picture, here and from another Mac.
  @MainActor @Test func aVideoKeptAsSoundOnlyShowsItsCover() throws {
    #expect(!PlayerSource.file(LocalFile(URL(filePath: "/Loci/library/talk/media.m4a"))).showsPicture)
    #expect(PlayerSource.file(LocalFile(URL(filePath: "/Loci/library/talk/media.mp4"))).showsPicture)
    let info = MediaFileInfo(byteCount: 100, fileExtension: "m4a")
    let ranged = try #require(RangedMedia(item: EntityID(), info: info, host: FakeHost(try Sample(problems: false))))
    #expect(!PlayerSource.ranges(ranged).showsPicture)
    let sound = OnlineStream(url: URL(string: "https://media.example.com/a.m4a")!, audioOnly: true)
    #expect(!PlayerSource.online(sound).showsPicture)
  }

  @Test func theClockShowsMinutesAndSecondsAndHoursOnceThereAreAny() {
    #expect(MediaTime.text(.seconds(680)) == "11:20")
    #expect(MediaTime.text(.seconds(3825)) == "1:03:45")
    #expect(MediaTime.text(.milliseconds(59_999)) == "0:59")
    #expect(MediaTime.progress(at: .seconds(680), of: .seconds(2052)) == "11:20 / 34:12")
  }

  @Test func aLengthNotKnownYetReadsAsDashes() {
    #expect(MediaTime.progress(at: .zero, of: .zero) == "0:00 / --:--")
    #expect(MediaTime.remaining(at: .zero, of: .zero) == "--:--")
  }

  @Test func whatIsLeftReadsWithAMinusSign() {
    #expect(MediaTime.remaining(at: .seconds(1101), of: .seconds(4323)) == "\u{2212}53:42")
  }

  @Test func speedStepsThroughItsStopsAndHoldsAtEitherEnd() {
    #expect(PlaybackSpeed.normal.faster == .quarterFaster)
    #expect(PlaybackSpeed.normal.slower == .threeQuarters)
    #expect(PlaybackSpeed.double.faster == .double)
    #expect(PlaybackSpeed.half.slower == .half)
  }

  @Test func speedAlwaysShowsAtLeastOneDecimal() {
    #expect(PlaybackSpeed.normal.label == "1.0×")
    #expect(PlaybackSpeed.quarterFaster.label == "1.25×")
    #expect(PlaybackSpeed.halfFaster.label == "1.5×")
  }

  @Test func eachSubtitleModeShowsItsLines() {
    let below = SubtitleStyle.BilingualOrder.originalAbove
    #expect(SubtitleMode.original.lines(of: "Hi", translated: "你好", order: below).map(\.text) == ["Hi"])
    #expect(SubtitleMode.both.lines(of: "Hi", translated: "你好", order: below).map(\.text) == ["Hi", "你好"])
    #expect(SubtitleMode.translation.lines(of: "Hi", translated: "你好", order: below).map(\.text) == ["你好"])
  }

  @Test func withoutATranslationEveryModeShowsTheOriginal() {
    for mode in SubtitleMode.allCases {
      #expect(mode.lines(of: "Hi", translated: nil, order: .translationAbove).map(\.text) == ["Hi"])
    }
  }

  @Test func aTranslationThatDoesNotFitIsNotShown() throws {
    let transcript = try Self.transcript([0, 5, 10])
    let short = try Translation(language: "zh-Hans", lines: ["一", "二"])
    let readable = ReadableTranscript(transcript: transcript, translations: [short], language: "zh-Hans")
    #expect(readable.translation == nil)
    #expect(readable.lines(0, mode: .both, order: .originalAbove).map(\.text) == ["s0"])
  }

  @Test func theTranslationIntoTheReadersLanguageIsChosen() throws {
    let transcript = try Self.transcript([0, 5])
    let french = try Translation(language: "fr", lines: ["un", "deux"])
    let chinese = try Translation(language: "zh-Hans", lines: ["一", "二"])
    let readable = ReadableTranscript(transcript: transcript, translations: [french, chinese], language: "zh-Hans")
    #expect(readable.lines(1, mode: .both, order: .originalAbove).map(\.text) == ["s1", "二"])
  }

  @Test func theSentencePlayingIsTheLastToHaveStarted() throws {
    let segments = try Self.transcript([0, 5, 10]).segments
    #expect(TranscriptFollow.playing(in: segments, at: .seconds(6)) == 1)
    #expect(TranscriptFollow.playing(in: segments, at: .seconds(10)) == 2)
    #expect(TranscriptFollow.playing(in: segments, at: .seconds(99)) == 2)
  }

  @Test func aPauseBetweenSentencesKeepsTheEarlierOne() throws {
    let segments = try Self.transcript([0, 10]).segments
    #expect(TranscriptFollow.playing(in: segments, at: .seconds(8)) == 0)
  }

  @Test func beforeTheFirstSentenceNothingIsPlaying() throws {
    let segments = try Self.transcript([3]).segments
    #expect(TranscriptFollow.playing(in: segments, at: .seconds(1)) == nil)
  }

  @Test func scrollingByHandStopsFollowingUntilBackToPlaying() {
    var follow = TranscriptFollow()
    #expect(follow.following)
    follow.scrolledByHand()
    #expect(!follow.following)
    follow.resume()
    #expect(follow.following)
  }

  @Test func chaptersCutTheBarWhereTheyBegin() throws {
    let outline = try Outline(
      chapters: [
        Outline.Chapter(start: .zero, title: "Intro"), Outline.Chapter(start: .seconds(25), title: "Filter"),
      ])
    let timeline = Timeline(length: .seconds(100), outline: outline)
    #expect(timeline.cuts == [0.25])
    #expect(timeline.chapter(at: .seconds(30))?.title == "Filter")
    #expect(timeline.chapter(at: .seconds(3))?.title == "Intro")
  }

  @Test func keyPointsSitInProportionToTheLength() throws {
    let point = try KeyPoint(
      place: .time(try TimeSpan(start: .seconds(50), end: .seconds(60))), title: "Why", reason: "Because")
    let timeline = Timeline(length: .seconds(200), outline: nil, keyPoints: [point])
    #expect(timeline.keyPoints == [0.25...0.3])
  }

  @Test func aShareOfTheBarIsAMomentInTheMedia() {
    let timeline = Timeline(length: .seconds(200), outline: nil)
    #expect(timeline.time(at: 0.5) == .seconds(100))
    #expect(timeline.time(at: 2) == .seconds(200))
  }

  static func transcript(_ starts: [Int]) throws -> Transcript {
    try Transcript(
      language: "en", origin: .platform,
      segments: starts.enumerated().map { index, start in
        try Transcript.Segment(start: .seconds(start), end: .seconds(start + 4), text: "s\(index)")
      })
  }
}

extension PlayerTests {
  @Test func aChapterHeadsItsFirstSentenceAndEmptyChaptersAreLeftOut() throws {
    let segments = try Self.transcript([100, 200]).segments
    let chapters = try [0, 50, 150].map { try Outline.Chapter(start: .seconds($0), title: "c\($0)") }
    let lines = TranscriptLayout.lines(segments, chapters: chapters, showSpeakers: false).map(\.id)
    #expect(lines == ["c50000", "s0", "c150000", "s1"])
  }

  @Test func modelSizesReadInDecimalUnits() {
    #expect(SpeechModel.tiny.sizeText == "77.7 MB")
    #expect(SpeechModel.medium.sizeText == "1.53 GB")
    #expect(SpeechModel.base.sizeText == "148 MB")
  }
}

@MainActor
extension PlayerTests {
  @Test func pressingPlayBeforeMediaIsAvailableDoesNotShowPause() {
    let player = Player(start: .zero, length: .seconds(19))

    player.play()

    #expect(!player.playing)
  }

  @Test func anUnreadableFileStopsPlaybackAndSaysItCannotPlay() async throws {
    let url = URL(filePath: "/tmp/\(UUID()).mp4")
    let player = Player(start: .zero, length: .seconds(19))
    defer { player.close() }
    player.load(.file(LocalFile(url)))
    player.play()

    try await eventually("the unavailable file to stop playing") { player.availability == .failed }

    #expect(!player.playing)
  }
}
