import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// CH-S1–CH-S5: the chat with the companion in its corner, and its home page, in light and dark.
@MainActor
@Suite(.serialized, .onStage)
struct CompanionHomeSnapshots {
  private static func defaults(sidebarShown: Bool = true, tab: LociTab? = nil) -> UserDefaults {
    let defaults = LibrarySnapshots.defaults(panel: true)
    defaults.set(sidebarShown, forKey: "sidebarShown")
    if let tab { defaults.set(tab.rawValue, forKey: LociTab.key) }
    return defaults
  }

  /// CH-S2: with the sidebar hidden, the companion's corner makes room for the window's buttons.
  @Test(arguments: Snapshot.Appearance.allCases)
  func chatWithTheSidebarHidden(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "talk-sidebar-hidden", try SampleLibrary(), at: WindowState(), appearance: appearance,
      defaults: Self.defaults(sidebarShown: false))
  }

  /// CH-S2, CH-S4: a sleepy companion has a gray dot and says so under its name.
  @Test(arguments: Snapshot.Appearance.allCases)
  func chatWithASleepyCompanion(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "talk-sleepy", try SampleLibrary(), at: WindowState(), appearance: appearance,
      presence: LociPresence(tiredness: .sleepy, lastSaid: "先睡了，明早接着看抢占那段。"))
  }

  /// CH-S5: the home page opens at the tab last looked at.
  @Test(arguments: [LociTab.soul, .models, .connectors], Snapshot.Appearance.allCases)
  func home(tab: LociTab, appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "home-\(tab)", try SampleLibrary(), at: WindowState(place: .loci), appearance: appearance,
      defaults: Self.defaults(tab: tab))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func homeInEnglish(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "home-en", try SampleLibrary(), at: WindowState(place: .loci), appearance: appearance, english: true,
      defaults: Self.defaults(tab: .soul))
  }

  /// CH-S5: scrolled down, the tabs stay at the top and the companion's small face and name show above them.
  @Test(arguments: Snapshot.Appearance.allCases)
  func homeScrolled(appearance: Snapshot.Appearance) async throws {
    let view = HStack(spacing: 0) { LociScreen(LociScreen.Opening(tab: .memory), back: {}, message: {}) }
      .defaultScrollAnchor(.bottom)
      .lociHost(FakeHost(try Sample(problems: false), library: try SampleLibrary()))
      .environment(\.companionName, "小满")
    try await ScreenSnapshots.shoot(
      "home-scrolled", view, appearance: appearance, size: CGSize(width: 1036, height: 520))
  }
}
