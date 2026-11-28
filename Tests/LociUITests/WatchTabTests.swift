import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// WT-S12: the Watch page, the chat and the projects beside the chosen one's `WATCH.md`.
@MainActor
@Suite(.serialized, .onStage)
struct WatchTabTests {
  @Test func theSheetLeavesOutTheHeadingItsTitleAlreadySays() {
    #expect(WatchTab.shown("# Watch\n\n- 噪音\n") == "- 噪音")
    #expect(WatchTab.shown("# Watch\n") == "")
    #expect(WatchTab.shown("稳市政策要告诉我\n") == "稳市政策要告诉我")
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func watchOfTheChat(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-watch", appearance: appearance, chosen: .chat)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func watchOfAnEmptyProject(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-watch-project", appearance: appearance, chosen: .project(ProjectSnapshots.trip.id))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func watchInEnglish(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-watch-en", appearance: appearance, chosen: .chat, english: true)
  }

  private func shoot(
    _ name: String, appearance: Snapshot.Appearance, chosen: Home, english: Bool = false
  ) async throws {
    let view = HStack(spacing: 0) { LociScreen(LociScreen.Opening(tab: .watch, watch: chosen)) }
      .lociHost(FakeHost(try Sample(problems: false), library: try SampleLibrary(), projects: ProjectSnapshots.bar))
    try await ScreenSnapshots.shoot(
      name, view, appearance: appearance, english: english, size: CGSize(width: 1036, height: 900))
  }
}
