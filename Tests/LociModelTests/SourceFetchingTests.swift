import Foundation
import Testing

@testable import LociModel

/// DS-S2, DS-S5, DS-S6, DS-S7: when a source is fetched, what else it may read, when it is broken, and the
/// entries it may give.
struct SourceFetchingTests {
  static func json(_ text: String) -> JSONValue { JSONValue(parsing: text)! }
  static let shanghai = TimeZone(identifier: "Asia/Shanghai")!
  /// 2025-11-17 10:00 in Shanghai, a Monday.
  static let monday = Timestamp(millisecondsSince1970: 1_763_344_800_000)

  static func at(minutes: Int64, from start: Timestamp = monday) -> Timestamp {
    Timestamp(millisecondsSince1970: start.millisecondsSince1970 + minutes * 60_000)
  }

  static func source(every minutes: Int, window: SourceWindow? = nil) -> DataSource {
    DataSource(name: "quote", title: "行情", every: SourceEvery(minutes: minutes)!, window: window, script: "x")
  }

  @Test func aSourceIsDueAsOftenAsItSaysInFrontAndAtMostHourlyBehind() {
    func due(_ source: DataSource, after minutes: Int64, inFront: Bool) -> Bool {
      SourceSchedule.due(
        source, tried: Self.monday, now: Self.at(minutes: minutes), inFront: inFront, timeZone: Self.shanghai)
    }

    #expect(due(Self.source(every: 1), after: 1, inFront: true))
    #expect(!due(Self.source(every: 15), after: 14, inFront: true))
    #expect(!due(Self.source(every: 1), after: 59, inFront: false))
    #expect(due(Self.source(every: 1), after: 60, inFront: false))
    #expect(!due(Self.source(every: 120), after: 60, inFront: false))
    #expect(
      SourceSchedule.due(Self.source(every: 60), tried: nil, now: Self.monday, inFront: false, timeZone: Self.shanghai))
  }

  @Test func aSourceWithAWindowIsDueOnlyInIt() {
    let window = SourceWindow("09:30-15:00", weekdays: true)!
    let source = Self.source(every: 1, window: window)
    let saturday = Self.at(minutes: 5 * 24 * 60)

    #expect(window.contains(Self.monday, in: Self.shanghai))
    #expect(!window.contains(Self.at(minutes: -31), in: Self.shanghai))
    #expect(!window.contains(Self.at(minutes: 300), in: Self.shanghai))
    #expect(!window.contains(saturday, in: Self.shanghai))
    #expect(SourceWindow("09:30-15:00")!.contains(saturday, in: Self.shanghai))
    #expect(!SourceSchedule.due(source, tried: nil, now: saturday, inFront: true, timeZone: Self.shanghai))
  }

  @Test func requestsMayAlsoBeAPageOrAConnectorsReadOnlyTool() throws {
    let requests = try DataSourceCheck.requests(
      from: Self.json(
        #"[{ "page": "https://x.com/umupa" }, { "connector": "github", "tool": "gh", "arguments": { "args": ["api", "x"] } }]"#
      ))

    #expect(
      requests == [
        .page(URL(string: "https://x.com/umupa")!),
        .connector(
          SourceConnectorCall(
            connector: ConnectorID(rawValue: "github"), tool: "gh",
            arguments: .object(["args": .array([.string("api"), .string("x")])]))),
      ])
    #expect(requests[1].address.absoluteString == "connector://github/gh")
    #expect(throws: SourceProblems("requests[0].page", "\"file:///x\" is not an http(s) link")) {
      try DataSourceCheck.requests(from: Self.json(#"[{ "page": "file:///x" }]"#))
    }
    #expect(throws: SourceProblems("requests[0].arguments", "is not an object")) {
      try DataSourceCheck.requests(from: Self.json(#"[{ "connector": "github", "tool": "gh", "arguments": [] }]"#))
    }
  }

  @Test func aSampleKeptBeforePagesAndConnectorsReadsAsAGet() throws {
    let kept = Data(#"{ "url": "https://qt.gtimg.cn/q=a", "encoding": "gbk" }"#.utf8)

    let request = try JSONDecoder().decode(SourceRequest.self, from: kept)

    #expect(request == .get(SourceGet(url: URL(string: "https://qt.gtimg.cn/q=a")!, encoding: .gbk)))
    for request in [request, .page(URL(string: "https://x.com")!)] {
      #expect(try JSONDecoder().decode(SourceRequest.self, from: JSONEncoder().encode(request)) == request)
    }
  }

  @Test func parseMayGiveEntriesKnownByTheirIds() throws {
    let output = try DataSourceCheck.output(
      from: Self.json(
        #"{ "entries": [{ "id": 7, "title": "纳指走高", "url": "https://a.example/7", "at": 1763344800000, "note": "+1%" }, { "id": "8", "title": "港股" }] }"#
      ))

    #expect(output.records.isEmpty)
    #expect(
      output.entries == [
        SourceEntry(
          id: "7", title: "纳指走高", url: URL(string: "https://a.example/7"), at: Self.monday, note: "+1%"),
        SourceEntry(id: "8", title: "港股"),
      ])
    #expect(
      throws: SourceProblems(all: [
        SourceProblem("entries[0]", "needs an \"id\" and a \"title\""),
        SourceProblem("entries[2].id", "\"8\" is given twice"),
      ])
    ) {
      try DataSourceCheck.output(
        from: Self.json(#"{ "entries": [{ "id": "7" }, { "id": "8", "title": "a" }, { "id": "8", "title": "b" }] }"#))
    }
  }

  @Test func aSourceIsBrokenAfterItsScriptFailsThreeTimesInARow() {
    let got = SourceSnapshot(fetched: Self.monday, records: ["a": ["v": .number(1)]])
    let problems = SourceProblems("parse", "fields[3] is undefined")

    let twice = got.failed(at: Self.at(minutes: 1), script: problems).failed(at: Self.at(minutes: 2), script: problems)
    let unreachable = twice.failed(at: Self.at(minutes: 3))
    let thrice = unreachable.failed(at: Self.at(minutes: 4), script: problems)

    #expect(!twice.isBroken && !unreachable.isBroken)
    #expect(thrice.isBroken)
    #expect(thrice.breakage == SourceBreakage(since: Self.at(minutes: 1), failures: 3, problems: problems.all))
    #expect(thrice.records == got.records && thrice.failures == 4)
  }

  @Test func aPanelLetsThroughOnlyEntriesWithNoSkippedWord() {
    let feed = PanelFeed(source: "news", skip: ["广告", "Sponsored"])

    #expect(feed.admits(SourceEntry(id: "1", title: "纳指走高")))
    #expect(!feed.admits(SourceEntry(id: "2", title: "某券商开户广告")))
    #expect(!feed.admits(SourceEntry(id: "3", title: "A sponsored post")))
  }
}
