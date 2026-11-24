import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// The panel column beside the main conversation, in light and dark, in each state the design draws. The
/// window reads the column, covers and pictures from the host, as the app does.
@MainActor
@Suite(.serialized, .onStage)
struct PanelSnapshots {
  /// The design's window.
  static let window = CGSize(width: 1440, height: 900)
  static let lane = CGSize(width: 380, height: 900)

  static let actions = PanelActions(
    open: { _ in }, openItem: { _ in }, ask: { _ in }, create: {}, revise: { _ in }, refresh: { _ in },
    moveToTop: { _ in }, remove: { _ in }, edit: { _ in true }, mark: { _ in true })

  /// Where the window remembers the column folded or not, apart from the app's own preferences.
  static func defaults(columnShown: Bool, sidebarShown: Bool, layout: TalkLayout?) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "loci-panel-snapshots") ?? .standard
    defaults.set(columnShown, forKey: "panelColumnShown")
    defaults.set(sidebarShown, forKey: "sidebarShown")
    if let layout, let data = try? JSONEncoder().encode(layout) {
      defaults.set(data, forKey: TalkLayout.key)
    } else {
      defaults.removeObject(forKey: TalkLayout.key)
    }
    return defaults
  }

  static func shoot(
    _ name: String, columnShown: Bool = true, sidebarShown: Bool = true, english: Bool = false,
    layout: TalkLayout? = nil, size: CGSize = window, reads: Bool = false, appearance: Snapshot.Appearance
  ) async throws {
    try await LibrarySnapshots.shoot(
      name, try SampleLibrary(), at: WindowState(), appearance: appearance, english: english, size: size,
      panels: try SamplePanels.column(reads: reads),
      defaults: defaults(columnShown: columnShown, sidebarShown: sidebarShown, layout: layout))
  }

  /// The sample panels by key, as the column lists them.
  static func keys(reads: Bool) throws -> [String] {
    try SamplePanels.column(reads: reads).slots.map(\.key)
  }

  /// P-S12, P-S15: panels on both sides of the conversation in a wide window.
  @Test(arguments: Snapshot.Appearance.allCases)
  func bothSides(appearance: Snapshot.Appearance) async throws {
    let layout = TalkLayout.standard.holding(try Self.keys(reads: true)).arranged(.panelsBothSides)
    try await Self.shoot(
      "talk-both-sides", layout: layout, size: CGSize(width: 1800, height: 1000), reads: true, appearance: appearance)
  }

  /// P-S12: the panels moved to the left of the conversation.
  @Test(arguments: Snapshot.Appearance.allCases)
  func panelsOnTheLeft(appearance: Snapshot.Appearance) async throws {
    let layout = TalkLayout.standard.holding(try Self.keys(reads: true)).arranged(.panelsLeft)
    try await Self.shoot("talk-panels-left", layout: layout, reads: true, appearance: appearance)
  }

  /// P-S16: in a narrow window the lanes fold to their marks.
  @Test(arguments: Snapshot.Appearance.allCases)
  func foldedToRails(appearance: Snapshot.Appearance) async throws {
    let layout = TalkLayout.standard.holding(try Self.keys(reads: true)).arranged(.panelsBothSides)
    try await Self.shoot(
      "talk-rails", layout: layout, size: CGSize(width: 1100, height: 860), reads: true, appearance: appearance)
  }

  /// The column alone, read through the host.
  static func alone(_ view: some View) throws -> some View {
    view
      .background(Palette.canvas)
      .environment(\.covers, Covers())
      .environment(\.panelPictures, PanelPictures())
      .lociHost(FakeHost(try Sample(problems: false)))
  }

  /// P-S1, P-S2, P-S3, P-S5: the column beside the conversation in the window, every kind of row in it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func column(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("panels", appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func columnInEnglish(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("panels-en", english: true, appearance: appearance)
  }

  /// P-S1: the column folded away; the button that brings it back stays.
  @Test(arguments: Snapshot.Appearance.allCases)
  func folded(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("panels-folded", columnShown: false, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func bothSidePanesCanStartFolded(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("sidebar-and-panels-folded", columnShown: false, sidebarShown: false, appearance: appearance)
  }

  /// P-S2, P-S3: the whole column: the paging panels on their second page and opened out, and the panel with
  /// numbers, covers and a picture.
  @Test(arguments: Snapshot.Appearance.allCases)
  func pagedAndOpenedOut(appearance: Snapshot.Appearance) async throws {
    let view = PanelLaneView(
      slots: try SamplePanels.column().slots, actions: Self.actions, opened: ["sandbox-radar", "sandbox-reads"],
      pages: ["sandbox-radar": 1, "job-radar": 1])
    try await ScreenSnapshots.shoot(
      "panels-pages", try Self.alone(view), appearance: appearance, size: CGSize(width: 380, height: 3000))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func onlyTheFoldedLongPanelPreviewsTheNextRow(appearance: Snapshot.Appearance) async throws {
    let view = HStack(alignment: .top, spacing: Spacing.s) {
      VStack(spacing: Spacing.s) {
        PanelCard(panel: SamplePanels.radar, actions: Self.actions)
        PanelCard(panel: SamplePanels.feed, actions: Self.actions)
      }
      PanelCard(panel: SamplePanels.radar, actions: Self.actions, open: true)
    }
    .padding(Spacing.s)
    .frame(maxHeight: .infinity, alignment: .top)
    try await ScreenSnapshots.shoot(
      "panels-overflow", try Self.alone(view), appearance: appearance, size: CGSize(width: 760, height: 740))
  }

  /// P-S6: the composer asking for a new panel over the blurred conversation.
  @Test(arguments: Snapshot.Appearance.allCases)
  func asking(appearance: Snapshot.Appearance) async throws {
    let column = try SamplePanels.column(reads: false)
    let view = HStack(spacing: 0) {
      ConversationScreen(
        ref: .main, draft: .constant(nil), revealPassage: { _ in },
        panelRequest: PanelRequest(making: .constant(true)))
      PanelLaneView(slots: column.slots, foot: true, making: true, actions: Self.actions).frame(width: 380)
    }
    .overlay(alignment: .topTrailing) {
      PanelButton(title: .loci("panels.hideColumn"), action: {}).padding(Spacing.s)
    }
    .environment(\.standIns, StandIns())
    try await ScreenSnapshots.shoot(
      "panels-asking", try Self.alone(view), appearance: appearance, size: CGSize(width: 1200, height: 900))
  }

  /// P-S6: after asking for a panel that reads Hacker News and the library, the skeleton at the column's foot,
  /// marked with both, scrolled to.
  @Test(arguments: Snapshot.Appearance.allCases)
  func building(appearance: Snapshot.Appearance) async throws {
    let request = PanelSources.named(
      in: "每周从 Hacker News 挑三篇和我资料库有关的文章", locale: Locale(identifier: "zh-Hans"))
    let view = PanelLaneView(
      slots: try SamplePanels.column(reads: false).slots, foot: true, building: request, actions: Self.actions
    )
    .environment(\.standIns, StandIns())
    try await ScreenSnapshots.shoot("panels-building", try Self.alone(view), appearance: appearance, size: Self.lane)
  }
}
