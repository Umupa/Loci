import Foundation
import LociModel
import Testing

@testable import LociHost

/// BK-S12: a book on the studio is taken in, read and kept track of from the laptop.
@Suite(.timeLimit(.minutes(1)))
struct RemoteBookTests {
  @Test func theLaptopReadsABookOnTheStudioAndThePlaceIsKeptThere() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let file = macs.laptop.place.root.appending(path: ".outside/吶喊.epub")
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try BookScenarioTests.epub().write(to: file)

      let item = try await remote.run(ImportBook(upload: try await remote.upload(LocalFile(file))))
      let contents = try await remote.run(ReadBookContents(item: item.id))
      let page = try await remote.run(ReadBookFile(item: item.id, path: contents.chapters[0].path))
      let spot = Locator.item(item.id, .spot(try BookSpot(chapter: 0, node: [0], character: 2, share: Fraction(0.5))))
      _ = try await remote.run(SaveReadingPosition(content: .item(item.id), position: spot))

      #expect(String(decoding: page, as: UTF8.self).contains("月光"))
      #expect(try await macs.studio.local.listItems().map(\.id) == [item.id])
      #expect(try await macs.studio.local.readingState(of: .item(item.id))?.position == spot)
      #expect(try await macs.laptop.local.listItems().isEmpty)
    }
  }
}
