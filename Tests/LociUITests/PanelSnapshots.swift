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
  static let column = CGSize(width: Size.panelColumn, height: 900)

  static let actions = PanelActions(
    open: { _ in }, openItem: { _ in }, ask: { _ in }, create: {}, revise: { _ in }, refresh: { _ in },
    moveToTop: { _ in }, remove: { _ in })

  /// Where the window remembers the column folded or not, apart from the app's own preferences.
  static func defaults(columnShown: Bool) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "loci-panel-snapshots") ?? .standard
    defaults.set(columnShown, forKey: "panelColumnShown")
    return defaults
  }

  static func shoot(
    _ name: String, columnShown: Bool = true, english: Bool = false, appearance: Snapshot.Appearance
  ) async throws {
    try await LibrarySnapshots.shoot(
      name, try SampleLibrary(), at: WindowState(), appearance: appearance, english: english, size: window,
      panels: try SamplePanels.column(reads: false), defaults: defaults(columnShown: columnShown))
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

  /// P-S2, P-S3: the whole column: the paging panels on their second page and opened out, and the panel with
  /// numbers, covers and a picture.
  @Test(arguments: Snapshot.Appearance.allCases)
  func pagedAndOpenedOut(appearance: Snapshot.Appearance) async throws {
    let view = PanelColumnView(
      column: try SamplePanels.column(), actions: Self.actions, opened: ["sandbox-radar", "sandbox-reads"],
      pages: ["sandbox-radar": 1, "job-radar": 1])
    try await ScreenSnapshots.shoot(
      "panels-pages", try Self.alone(view), appearance: appearance,
      size: CGSize(width: Size.panelColumn, height: 3000))
  }

  /// P-S6: the composer asking for a new panel over the blurred conversation.
  @Test(arguments: Snapshot.Appearance.allCases)
  func asking(appearance: Snapshot.Appearance) async throws {
    let column = try SamplePanels.column(reads: false)
    let view = HStack(spacing: 0) {
      ConversationScreen(
        ref: .main, draft: .constant(nil), revealPassage: { _ in },
        panelRequest: PanelRequest(making: .constant(true)))
      PanelColumnView(column: column, making: true, actions: Self.actions).frame(width: Size.panelColumn)
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
    let view = PanelColumnView(
      column: try SamplePanels.column(reads: false), building: request, actions: Self.actions
    )
    .environment(\.standIns, StandIns())
    try await ScreenSnapshots.shoot("panels-building", try Self.alone(view), appearance: appearance, size: Self.column)
  }
}
