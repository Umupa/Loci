import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// P-S17–P-S21: panels the person writes in, in light and dark, in each state the design draws.
@MainActor
@Suite(.serialized, .onStage)
struct PanelItemSnapshots {
  static let size = CGSize(width: 392, height: 1180)

  static func shoot(
    _ name: String, look: PanelItemsLook = PanelItemsLook(), allDone: Bool = false, arrived: Set<String> = [],
    open: Bool = true, appearance: Snapshot.Appearance
  ) async throws {
    let view = VStack(spacing: Spacing.s) {
      ForEach(SampleItemPanels.slots(allDone: allDone), id: \.key) { slot in
        if case .panel(let panel) = slot {
          PanelCard(
            panel: panel, actions: PanelSnapshots.actions, marks: SampleItemPanels.marks[panel.name] ?? [:],
            open: open, arrived: arrived)
        }
      }
    }
    .padding(Spacing.s)
    .frame(maxHeight: .infinity, alignment: .top)
    .environment(\.panelItemsLook, look)
    try await ScreenSnapshots.shoot(
      name, try PanelSnapshots.alone(view), appearance: appearance, size: size)
  }

  /// P-S17, P-S20, P-S21: the person's items and Loci's with its face, Loci's suggestions with dashed circles,
  /// a pinned item, notes in slanted serif, done items folded into dots, and the radar with a pinned, noted
  /// line and a hidden one left out.
  @Test(arguments: Snapshot.Appearance.allCases)
  func items(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("panel-items", appearance: appearance)
  }

  /// P-S18: words typed into this week's empty row, the pointer on the promises' empty row, and today's done
  /// items opened out.
  @Test(arguments: Snapshot.Appearance.allCases)
  func typing(appearance: Snapshot.Appearance) async throws {
    let look = PanelItemsLook(typed: ["week": "约 Lin 周三下午聊"], pointed: ["all"], opened: ["today"])
    try await Self.shoot("panel-items-typing", look: look, appearance: appearance)
  }

  /// P-S18: everything today done; the ring before the title is full and amber.
  @Test(arguments: Snapshot.Appearance.allCases)
  func allDone(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("panel-items-done", allDone: true, appearance: appearance)
  }

  /// P-S2: a long panel of items is cut where an item ends, inside a section, not only where one ends.
  @Test(arguments: Snapshot.Appearance.allCases)
  func cut(appearance: Snapshot.Appearance) async throws {
    let look = PanelItemsLook(opened: ["today"])
    try await Self.shoot("panel-items-cut", look: look, open: false, appearance: appearance)
  }

  /// P-S23: an item Loci just added, ringed in amber.
  @Test(arguments: Snapshot.Appearance.allCases)
  func arrived(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("panel-items-arrived", arrived: ["kata"], appearance: appearance)
  }
}
