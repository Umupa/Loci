import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

@MainActor
@Suite(.serialized, .onStage)
struct ArticleFetchSnapshots {
  @Test(arguments: Snapshot.Appearance.allCases)
  func theReaderShowsTheTitleAndSourceWhileTheTextIsBeingRead(appearance: Snapshot.Appearance) async throws {
    let item = try SampleLibrary().article
    let job = Job(item: item.id, stage: .extract, state: .running(progress: nil), stages: Self.stages)
    let file = try await Snapshot.render(
      FetchingItem(item: item, job: job), named: "article-fetching", appearance: appearance)
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func theArticleCardShowsWhyThePageFailed(appearance: Snapshot.Appearance) async throws {
    let item = try SampleLibrary().article
    let job = Job(
      item: item.id, stage: .fetchPage, state: .failed(.init(reason: "Connection timed out", cause: .network)),
      stages: Self.stages)
    let actions = CardActions(pause: { _ in }, resume: { _ in }, cancel: { _ in }, fix: { _, _ in })
    let width: CGFloat = 246
    let view = GalleryCard(item: item, job: job, share: nil, chosen: false, actions: actions, coverWidth: width)
      .frame(width: width)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Palette.canvas)
      .environment(\.standIns, StandIns())
    let file = try await Snapshot.render(
      view, named: "article-fetch-failed", size: CGSize(width: 320, height: 240), appearance: appearance)
    #expect(try Data(contentsOf: file).count > 5_000)
  }

  private static let stages: [Job.Stage] = [.fetchPage, .extract, .findCover]
}
