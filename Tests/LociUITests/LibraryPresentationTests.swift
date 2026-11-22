import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

@MainActor
struct LibraryPresentationTests {
  @Test func videosAreWidescreenAndPodcastsAreSquare() {
    #expect(GalleryCard.coverRatio(for: .video) == 16.0 / 9)
    #expect(GalleryCard.coverRatio(for: .audio) == 1)
  }

  @Test func mixedCardsFillTheShortestColumnBeforeStartingFartherDown() {
    let heights: [CGFloat] = [160, 240, 180, 150, 220, 190]
    let frames = GalleryPlacement.frames(width: 644, count: heights.count) { index, _ in heights[index] }

    #expect(frames.map(\.width) == [200, 200, 200, 200, 200, 200])
    #expect(
      frames.map(\.origin) == [
        CGPoint(x: 0, y: 0), CGPoint(x: 222, y: 0), CGPoint(x: 444, y: 0),
        CGPoint(x: 0, y: 186), CGPoint(x: 444, y: 206), CGPoint(x: 222, y: 266),
      ])
  }

  @Test func aNarrowGalleryKeepsOneColumnInLibraryOrder() {
    let frames = GalleryPlacement.frames(width: 185, count: 3) { index, width in width + CGFloat(index) }

    #expect(frames.map(\.width) == [185, 185, 185])
    #expect(frames.map(\.minX) == [0, 0, 0])
    #expect(frames.map(\.minY) == [0, 211, 423])
  }

  @Test func aListShowsTheSavedPlaceInEachKindOfMaterial() throws {
    let item = try SampleLibrary().video.id
    let updatedAt = Timestamp(millisecondsSince1970: 1_763_337_600_000)
    func text(_ anchor: ItemAnchor, finished: Bool = false) -> Text {
      LibraryRow.readingPosition(ReadingState(position: .item(item, anchor), finished: finished, updatedAt: updatedAt))
    }
    let time = ItemAnchor.time(try TimeSpan(start: .seconds(680)))
    let commit = try #require(CommitID(String(repeating: "a", count: 40)))
    let code = try CodeLines(path: "Sources/Layout.swift", lines: 24...24, commit: commit)

    #expect(LibraryRow.readingPosition(nil) == Text(verbatim: "—"))
    #expect(text(time) == Text(verbatim: "11:20"))
    #expect(text(time, finished: true) == Text(.loci("talk.finished")))
    #expect(
      text(.quote(try TextQuote("Scaled Dot-Product Attention"))) == Text(verbatim: "Scaled Dot-Product Attention"))
    #expect(text(.page(try PageRegion(page: 6))) == Text(.loci("library.page \(6)")))
    #expect(text(.lines(code)) == Text(verbatim: "Layout.swift:24"))
  }
}
