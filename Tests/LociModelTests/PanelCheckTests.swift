import Foundation
import Testing

@testable import LociModel

/// P-S7: a panel Loci writes is checked before it is shown, and every problem is named where it is.
struct PanelCheckTests {
  static func problems(_ json: String, name: String = "radar") -> [String] {
    do throws(PanelProblems) {
      _ = try PanelCheck.read(Data(json.utf8), name: name)
      return []
    } catch {
      return error.all.map(\.description)
    }
  }

  static func panel(rows: String, refresh: String = #"{ "every": "day", "at": "10:00" }"#) -> String {
    #"{ "title": "雷达", "follow": "盯着新版本", "refresh": \#(refresh), "rows": [\#(rows)] }"#
  }

  static let sentence = #"{ "row": "sentence", "text": "**v0.8.0** 发布。" }"#

  @Test func aPanelThatMakesSenseIsReadWithTheNameItIsGiven() throws {
    let panel = try PanelCheck.read(Data(PanelCodingTests.written.utf8), name: "sandbox-radar")

    #expect(panel.name == "sandbox-radar")
    #expect(PanelCheck.problems(in: panel).isEmpty)
  }

  @Test func theNameInTheJSONGivesWayToTheFilesName() throws {
    let json = #"{ "name": "other", "title": "雷达", "follow": "x", "rows": [\#(Self.sentence)] }"#

    #expect(try PanelCheck.read(Data(json.utf8), name: "radar").name == "radar")
  }

  @Test func aPanelThatFollowsEntriesKeepsItsFeedAndHasNoFixedRefresh() throws {
    let feed = #"{ "source": "news", "skip": ["广告"] }"#
    let following = #"{ "title": "快讯", "follow": "x", "feed": \#(feed), "rows": [\#(Self.sentence)] }"#

    #expect(try PanelCheck.read(Data(following.utf8), name: "flash").feed == PanelFeed(source: "news"))
    #expect(
      Self.problems(
        #"{ "title": "快讯", "follow": "x", "feed": { "source": "News" }, "refresh": { "every": "hour" }, "rows": [\#(Self.sentence)] }"#
      )
        == [
          #"feed.source: "News" is not a short lowercase English name, such as etf-premium (at most 32)"#,
          "refresh: a panel with a feed is refreshed when its source has new entries; drop refresh",
        ])
  }

  @Test func anEmptyTitleOrFollowIsNamed() {
    let json = #"{ "title": " ", "follow": "", "rows": [\#(Self.sentence)] }"#

    #expect(Self.problems(json) == ["title: is empty", "follow: is empty; say what this panel follows"])
  }

  @Test func aPanelWithoutRowsIsNamed() {
    #expect(Self.problems(Self.panel(rows: "")) == ["rows: has no rows"])
    #expect(Self.problems(#"{ "title": "a", "follow": "b", "pages": [] }"#) == ["pages: has no pages"])
  }

  @Test func aPageWithoutRowsOrWithANameUsedBeforeIsNamed() {
    let json = """
      { "title": "a", "follow": "b", "pages": [
        { "name": "One", "rows": [\(Self.sentence)] },
        { "name": "Two", "rows": [] },
        { "name": "One", "rows": [\(Self.sentence)] }
      ] }
      """

    #expect(
      Self.problems(json) == [
        "pages[1].rows: has no rows", #"pages[2].name: "One" is used by an earlier page"#,
      ])
  }

  @Test func theFirstRowMustBeASentence() {
    let json = Self.panel(rows: #"{ "row": "label", "text": "可以认领" }, \#(Self.sentence)"#)

    #expect(Self.problems(json) == ["rows[0]: the first row must be a sentence that sums the panel up"])
  }

  @Test func fractionsAndProgressAreFromZeroToOne() {
    let json = """
      { "title": "a", "follow": "b", "pages": [
        { "name": "One", "rows": [\(Self.sentence)] },
        { "name": "Two", "rows": [\(Self.sentence),
          { "row": "list", "items": [{ "title": "t", "progress": -0.1 }] },
          { "row": "bars", "bars": [{ "name": "E2B", "fraction": 1.4, "value": "+1.2k" }] }
        ] }
      ] }
      """

    #expect(
      Self.problems(json) == [
        "pages[1].rows[1].items[0].progress: -0.1 is not from 0 to 1",
        "pages[1].rows[2].bars[0].fraction: 1.4 is not from 0 to 1",
      ])
  }

  @Test(arguments: [
    (#"{ "every": "day", "at": "9:30" }"#, [#"refresh.at: "9:30" is not a time written HH:mm, such as 09:30"#]),
    (#"{ "every": "day", "at": "25:00" }"#, [#"refresh.at: "25:00" is not a time written HH:mm, such as 09:30"#]),
    (#"{ "every": "day" }"#, ["refresh.at: is missing; write the time as HH:mm"]),
    (#"{ "every": "week", "at": "10:00" }"#, ["refresh.weekday: is missing; 1 is Sunday, 7 is Saturday"]),
    (
      #"{ "every": "week", "at": "10:00", "weekday": 8 }"#,
      ["refresh.weekday: 8 is not from 1 (Sunday) to 7 (Saturday)"]
    ),
    (#"{ "every": "day", "at": "10:00", "weekday": 2 }"#, [#"refresh.weekday: is only for "every": "week""#]),
    (#"{ "every": "hour" }"#, []),
    (#"{ "every": "week", "at": "10:00", "weekday": 1 }"#, []),
  ])
  func aRefreshSaysWhenInAWayTheAppCanKeep(refresh: String, expected: [String]) {
    #expect(Self.problems(Self.panel(rows: Self.sentence, refresh: refresh)) == expected)
  }

  @Test func linksAreWebPagesOrPlacesInTheLibrary() {
    let rows = """
      \(Self.sentence),
      { "row": "list", "items": [
        { "title": "a", "link": "https://github.com/x" },
        { "title": "b", "link": "loci://library/019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f#t=3" },
        { "title": "c", "link": "file:///etc/passwd", "cover": "ftp://x/y.png" }
      ] },
      { "row": "picture", "url": "javascript:alert(1)" }
      """

    #expect(
      Self.problems(Self.panel(rows: rows)) == [
        #"rows[1].items[2].link: "file:///etc/passwd" is not an http(s) or loci:// link"#,
        #"rows[1].items[2].cover: "ftp://x/y.png" is not an http(s) or loci:// link"#,
        #"rows[2].url: "javascript:alert(1)" is not an http(s) or loci:// link"#,
      ])
  }

  @Test func cellsAreOneToThreeAndRowsAreNotEmpty() {
    let cell = #"{ "label": "a", "value": "1" }"#
    let rows = """
      \(Self.sentence),
      { "row": "cells", "cells": [\(cell), \(cell), \(cell), \(cell)] },
      { "row": "list", "items": [] },
      { "row": "label", "text": "" }
      """

    #expect(
      Self.problems(Self.panel(rows: rows)) == [
        "rows[1].cells: has 4; give one to three", "rows[2].items: is empty", "rows[3].text: is empty",
      ])
  }

  @Test func aJSONThatDoesNotDecodeSaysWhere() {
    #expect(Self.problems("not json") == ["is not JSON"])
    #expect(
      Self.problems(Self.panel(rows: "\(Self.sentence), { \"row\": \"chart\" }")) == [
        "rows[1].row: is not one of the values it can be: sentence, cells, label, list, prominent, bars, picture, "
          + "items, quotes, line, ruler, allocation, heat, candles, zones"
      ])
    #expect(
      Self.problems(Self.panel(rows: "\(Self.sentence), { \"row\": \"bars\", \"bars\": [{ \"name\": \"a\" }] }")) == [
        "rows[1].bars[0].fraction: is missing"
      ])
    #expect(Self.problems(#"{ "title": 3, "follow": "b", "rows": [] }"#) == ["title: is not text"])
  }

  @Test(arguments: ["sandbox-radar", "hn", "gh2"])
  func aShortLowercaseNameIsANameForAPanel(name: String) {
    #expect(PanelCheck.problems(ofName: name).isEmpty)
  }

  @Test(arguments: ["Sandbox", "沙箱", "a b", "-a", "a--b", "", "../a", String(repeating: "a", count: 33)])
  func anyOtherNameIsRefused(name: String) {
    #expect(PanelCheck.problems(ofName: name).map(\.path) == ["name"])
  }

  @Test func panelCommandsSurviveTheWire() throws {
    let panel = Panel(name: "radar", title: "雷达", follow: "x", body: .rows([.sentence("a")]))

    #expect(try HostCodingTests.roundTrips(SavePanel(panel)))
    #expect(try HostCodingTests.roundTrips(RefreshPanel(PanelRef("radar"))))
    #expect(try HostCodingTests.roundTrips(MovePanelToTop(.reading, in: .chat)))
    #expect(try HostCodingTests.roundTrips(MovePanelToTop(.panel("radar"), in: .chat)))
    #expect(try HostCodingTests.roundTrips(RemovePanel(PanelRef("radar"))))
    #expect(try HostCodingTests.roundTrips(ListPanels()))
    #expect(try HostCodingTests.roundTrips(WatchPanelColumn()))
    #expect(
      try HostCodingTests.roundTrips(
        [PanelEntry(name: "radar", panel: panel, problems: [PanelProblem("title", "is empty")])]))
    let item = try Item(id: Fixture.item, kind: .article, title: "Borg")
    #expect(
      try HostCodingTests.roundTrips(
        PanelColumn(
          slots: [.reading([ReadingNow(item: item, progress: 0.4, minutesLeft: 12)]), .panel(panel)],
          refreshing: ["radar"])))
  }

  @Test func movingASlotNamesItsPlace() throws {
    let panel = Panel(name: "radar", title: "雷达", follow: "x", body: .rows([.sentence("a")]))

    #expect(MovePanelToTop(.panel(panel), in: .chat).place == .panel("radar"))
    #expect(MovePanelToTop(.reading([]), in: .chat).place == .reading)
  }

  @Test func theColumnFollowsPanelsReadingAndTitlesButNotTheLociPage() {
    let column = WatchPanelColumn()

    #expect(column.isAffected(by: [.loci(.panels)]))
    #expect(column.isAffected(by: [.reading(.item(Fixture.item))]))
    #expect(column.isAffected(by: [.item(Fixture.item)]))
    #expect(!column.isAffected(by: [.loci(.memory)]))
    #expect(!LociHome().isAffected(by: [.loci(.panels)]))
  }
}
