import AppKit
import LociModel
import Testing

@testable import LociUI

@MainActor
@Suite(.serialized, .onStage)
struct LibraryPresentationSnapshots {
  @Test(arguments: Snapshot.Appearance.allCases)
  func mixedGallery(appearance: Snapshot.Appearance) async throws {
    let activity = Activity()
    let quiet = Quiet(activity)
    try await LibrarySnapshots.shoot(
      "library-gallery-mixed", try Self.library(), at: WindowState(place: .library(nil)), appearance: appearance,
      standIns: StandIns(), activity: activity, until: { _ in quiet.settled() })
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func savedListPreference(appearance: Snapshot.Appearance) async throws {
    let defaults = LibrarySnapshots.defaults(panel: true)
    defaults.set(LibraryPresentation.list.rawValue, forKey: LibraryPresentation.key)
    let activity = Activity()
    let quiet = Quiet(activity)
    try await LibrarySnapshots.shoot(
      "library-list", try Self.library(), at: WindowState(place: .library(nil)), appearance: appearance,
      standIns: StandIns(), defaults: defaults, activity: activity, until: { _ in quiet.settled() })
  }

  @Test(arguments: Snapshot.Appearance.allCases, [false, true])
  func papersKeepTheirTypeInTheArticlesList(appearance: Snapshot.Appearance, english: Bool) async throws {
    let defaults = LibrarySnapshots.defaults(panel: true)
    defaults.set(LibraryPresentation.list.rawValue, forKey: LibraryPresentation.key)
    let name = english ? "library-articles-list-en" : "library-articles-list"
    try await LibrarySnapshots.shoot(
      name, try Self.library(), at: WindowState(place: .library(.article)), appearance: appearance,
      english: english, defaults: defaults)
  }

  private static func library() throws -> SampleLibrary {
    var library = try SampleLibrary()
    let paper = try Item(
      id: library.attention.id, kind: .paper, title: library.attention.title,
      source: library.attention.source, site: library.attention.site)
    library.items = library.items.map { $0.id == paper.id ? paper : $0 }
    let readAt = Timestamp(millisecondsSince1970: 1_763_337_610_000)
    library.states[paper.id] = ReadingState(
      position: .item(paper.id, .page(try PageRegion(page: 6))), finished: false, updatedAt: readAt)
    library.states[library.article.id] = ReadingState(
      position: .item(library.article.id, .quote(try TextQuote("How Pingora Works"))), finished: false,
      updatedAt: readAt)
    for id in try [paper.id, library.uring, library.named("大模型"), library.named("The Log")] {
      library.covers[id] = nil
    }
    library.jobs = []
    return library
  }
}
