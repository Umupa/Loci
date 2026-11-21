import Foundation
import Testing

@testable import LociModel

/// A panel reads from the JSON Loci writes, row by row, and survives the trip a remote host gives it.
struct PanelCodingTests {
  static let written = """
    {
      "title": "沙箱雷达",
      "sources": ["github.com"],
      "follow": "盯着 CubeSandbox 的新版本和 PR",
      "refresh": { "every": "day", "at": "10:00" },
      "pages": [
        {
          "name": "CubeSandbox",
          "rows": [
            { "row": "sentence", "text": "**v0.8.0** 正式版发布。" },
            { "row": "cells", "cells": [{ "label": "最新版本", "value": "v0.8.0", "note": "8 天前" }] },
            { "row": "label", "text": "可以认领" },
            { "row": "list", "items": [{ "title": "#244 集成指南", "subtitle": "good first issue", "ask": "帮我分析 #244" }] },
            { "row": "prominent", "title": "混元沙盒平台工程师" },
            { "row": "bars", "bars": [{ "name": "e2b-dev/E2B", "fraction": 1, "value": "+1.2k" }] },
            { "row": "picture", "url": "https://example.com/a.png" }
          ]
        }
      ]
    }
    """

  @Test func aPanelReadsFromTheJSONLociWrites() throws {
    let panel = try JSONDecoder().decode(Panel.self, from: Data(Self.written.utf8))

    #expect(panel.title == "沙箱雷达")
    #expect(panel.refresh == PanelRefresh(every: .day, at: "10:00"))
    guard case .pages(let pages) = panel.body else {
      Issue.record("expected pages, got \(panel.body)")
      return
    }
    #expect(pages[0].rows.first == .sentence("**v0.8.0** 正式版发布。"))
    #expect(pages[0].rows.contains(.prominent(title: "混元沙盒平台工程师", subtitle: nil)))
    #expect(pages[0].rows.last == .picture(URL(string: "https://example.com/a.png")!, link: nil))
  }

  @Test func aPanelSurvivesJSON() throws {
    let panel = Panel(
      name: "reading", title: "好文", follow: "每周三篇", refresh: PanelRefresh(every: .week, at: "10:00", weekday: 1),
      body: .rows([.sentence("这周三篇"), .list([PanelListItem(title: "一", number: 1, progress: 0.4)])]))

    #expect(try HostCodingTests.roundTrips(panel))
  }
}
