import Foundation
import Testing

@testable import LociModel

/// PJ-S2, DS-S14, NX-S9: a Mac paired with one a version older or newer still sees its panels: a column from
/// an older host has no readings, and an older Mac is sent a column without the pinned panels and chart rows
/// it cannot read.
struct PanelCompatibilityTests {
  /// The panel column as 1.8.3 sends it.
  static let olderColumn = """
    {"slots":[{"panel":{"_0":{"name":"radar","title":"雷达","follow":"x","rows":[{"row":"sentence","text":"新版本"}]}}}],
     "refreshing":["radar"],"marks":{}}
    """

  /// The kinds of row and slot 1.8.3 can read.
  static let olderRows: Set<String> = ["sentence", "cells", "label", "list", "prominent", "bars", "picture", "items"]
  static let olderSlots: Set<String> = ["reading", "panel"]

  static func id(_ seed: UInt64) -> EntityID {
    var entropy = SeededGenerator(seed: seed)
    return EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + Double(seed)), entropy: &entropy)
  }

  @Test func aColumnFromAnOlderHostIsReadWithNoReadings() throws {
    let column = try JSONDecoder().decode(PanelColumn.self, from: Data(Self.olderColumn.utf8))

    #expect(column.slots.count == 1)
    #expect(column.refreshing == ["radar"])
    #expect(column.readings == PanelReadings())
  }

  @Test func anOlderMacsRequestIsAnsweredWithoutPinnedPanelsAndChartRows() throws {
    let request = try JSONDecoder().decode(WatchPanelColumn.self, from: Data("{}".utf8))
    #expect(request.shape == nil && request.home == .chat)
    #expect(WatchPanelColumn(of: .chat).shape == PanelColumn.shape)

    let charts = try PanelCheck.read(Data(PanelChartTests.written.utf8), name: "money")
    let mixed = charts.with(body: .rows([.sentence("持仓稳")] + (try PanelChartTests.rows())))
    let column = PanelColumn(slots: [.panel(mixed), .pinned(Self.id(1), mixed)])
    let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(column.forOlderMacs))

    let slots = try #require((sent as? [String: Any])?["slots"] as? [[String: Any]])
    #expect(Set(slots.flatMap(\.keys)).isSubset(of: Self.olderSlots))
    let rows = slots.compactMap {
      (($0["panel"] as? [String: Any])?["_0"] as? [String: Any])?["rows"] as? [[String: Any]]
    }
    .flatMap { $0 }.compactMap { $0["row"] as? String }
    #expect(rows == ["sentence"])
  }
}
