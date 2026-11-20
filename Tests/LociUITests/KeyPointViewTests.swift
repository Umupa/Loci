import Foundation
import LociModel
import Testing

@testable import LociUI

/// K-S1, K-S5, K-S6: the key points page, playing only the key points, and an article folded to them.
@MainActor
struct KeyPointViewTests {
  static func stretch(_ start: Int, _ end: Int) throws -> KeyPoint {
    try KeyPoint(place: .time(try TimeSpan(start: .seconds(start), end: .seconds(end))), title: "T", reason: "R")
  }

  static var playback: KeyPointPlayback {
    get throws { KeyPointPlayback([try stretch(10, 20), try stretch(40, 50)]) }
  }

  @Test func onlyKeyPointsJumpsFromTheEndOfOneToTheStartOfTheNext() throws {
    let playback = try Self.playback
    #expect(playback.step(at: .seconds(15)) == .stay)
    #expect(playback.step(at: .seconds(20)) == .jump(to: .seconds(40)))
  }

  @Test func startingOutsideAKeyPointJumpsToTheNext() throws {
    #expect(try Self.playback.step(at: .seconds(2)) == .jump(to: .seconds(10)))
  }

  @Test func afterTheLastKeyPointPlaybackStops() throws {
    #expect(try Self.playback.step(at: .seconds(50)) == .stop)
    #expect(try Self.playback.step(at: .seconds(90)) == .stop)
  }

  @Test func theKeyPointPlayingIsTheOneTheTimeIsIn() throws {
    #expect(try Self.playback.playing(at: .seconds(45)) == 1)
    #expect(try Self.playback.playing(at: .seconds(30)) == nil)
  }

  @Test func aKeyPointReadsAsItsStretchAndLengthOrItsPassage() throws {
    #expect(KeyPointWords.place(try Self.stretch(70, 100)) == "1:10 — 1:40 · 0:30")
    let passage = try KeyPoint(place: .passage(try .init(number: 7, text: "P")), title: "T", reason: "R")
    #expect(KeyPointWords.place(passage) == "¶ 7")
  }

  static let article = """
    # Tail

    First paragraph.

    Second paragraph.

    ## A heading

    Third paragraph.

    ![](figure.png)

    Fourth paragraph.
    """

  @Test func onlyKeyPointsFoldsTheArticleBetweenThem() throws {
    let points = try [3, 6].map { number in
      try KeyPoint(
        place: .passage(try .init(number: number, text: KeyPassageLayout.passages(of: Self.article)[number - 1])),
        title: "T", reason: "R")
    }

    let parts = KeyPassageLayout(markdown: Self.article, points: points).parts

    #expect(
      parts == [
        .folded(["First paragraph."]), .key(number: 1, text: "Second paragraph."),
        .folded(["## A heading", "Third paragraph."]), .key(number: 2, text: "Fourth paragraph."),
      ])
  }

  @Test func aKeyPassageIsFoundInTheTextByItsWords() throws {
    let plain = "Tail\nFirst paragraph.\nSecond bold words here.\n"

    let range = try #require(KeyPassageLayout.range(of: "Second **bold** words here.", in: plain))

    #expect(range == NSRange(location: 22, length: 23))
  }
}
