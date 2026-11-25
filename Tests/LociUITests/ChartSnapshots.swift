import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// DS-S3, DS-S8–DS-S14: chart panels filled from their sources, in light and dark.
@MainActor
@Suite(.serialized, .onStage)
struct ChartSnapshots {
  static let size = CGSize(width: 1180, height: 1240)

  static func shoot(_ name: String, english: Bool = false, appearance: Snapshot.Appearance) async throws {
    let column = SampleChartPanels.column
    let panels = column.slots.compactMap { slot -> Panel? in if case .panel(let panel) = slot { panel } else { nil } }
    let lanes = [Array(panels.prefix(2)), Array(panels.dropFirst(2))]
    let view = HStack(alignment: .top, spacing: Spacing.m) {
      ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
        VStack(spacing: Spacing.s) {
          ForEach(lane, id: \.name) { panel in
            PanelCard(panel: panel, actions: PanelSnapshots.actions, open: true)
          }
        }
        .frame(width: 380)
      }
    }
    .padding(Spacing.m)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Palette.canvas)
    .environment(\.panelData, PanelData(readings: column.readings))
    .environment(\.fixedNow, SampleChartPanels.now.date)
    .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai") ?? .gmt)
    .lociHost(FakeHost(try Sample(problems: false), panels: column))
    try await ScreenSnapshots.shoot(name, view, appearance: appearance, english: english, size: size)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func charts(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("panel-charts", appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func chartsInEnglish(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("panel-charts-en", english: true, appearance: appearance)
  }
}
