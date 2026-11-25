import Foundation
import Testing

@testable import LociModel

/// DS-S1, DS-S3, DS-S4: what a source is, what its script may give, and how rows read its records.
struct DataSourceTests {
  static func json(_ text: String) -> JSONValue { JSONValue(parsing: text)! }

  @Test func aFieldIsWrittenSourceRecordField() {
    #expect(SourceField("etf-premium.513870.premium")?.record == "513870")
    #expect(SourceField("etf-premium.513870") == nil)
    #expect(SourceField("Etf.513870.premium") == nil)
    #expect(SourceField("etf..premium") == nil)
    #expect(SourceField("etf.sh.513870.premium") == nil)
  }

  @Test func howOftenIsWrittenInMinutesOrHours() {
    #expect(SourceEvery("1m")?.minutes == 1)
    #expect(SourceEvery("2h")?.minutes == 120)
    #expect(SourceEvery("60m")?.description == "1h")
    #expect(SourceEvery("0m") == nil)
    #expect(SourceEvery("5s") == nil)
  }

  @Test func aWindowRunsForwardWithinADay() {
    #expect(SourceWindow("09:30-15:00", weekdays: true)?.description == "09:30-15:00 on weekdays")
    #expect(SourceWindow("15:00-09:30") == nil)
    #expect(SourceWindow("9:30") == nil)
  }

  @Test func aKeyCarriesWhoseTheSourceIs() throws {
    let key = SourceKey(.chat, "etf-premium")

    #expect(key.description == "home/etf-premium")
    #expect(SourceKey("home/etf-premium") == key)
    #expect(SourceKey("elsewhere/x") == nil)
    let project = SourceKey(.project(Fixture.id(40)), "etf-premium")
    #expect(project.description == "projects/\(Fixture.id(40))/etf-premium")
    #expect(SourceKey(project.description) == project)
    #expect(try HostCodingTests.roundTrips([key: 1]))
  }

  @Test func aSourceWithoutANameTitleOrScriptIsNamed() {
    let source = DataSource(name: "ETF", title: " ", every: SourceEvery(minutes: 1)!, script: "")

    #expect(
      DataSourceCheck.problems(in: source).map(\.description) == [
        #"name: "ETF" is not a short lowercase English name, such as etf-premium (at most 32)"#,
        "title: is empty",
        "script: is empty; declare requests(state) and parse(responses, now)",
      ])
  }

  @Test func requestsAreLinksOrObjectsAndOnlyGET() throws {
    let requests = try DataSourceCheck.requests(
      from: Self.json(
        #"["https://qt.gtimg.cn/q=sh513100", { "url": "https://a.example/x", "referer": "https://a.example", "encoding": "GBK" }]"#
      ))

    #expect(requests.map(\.url.absoluteString) == ["https://qt.gtimg.cn/q=sh513100", "https://a.example/x"])
    #expect(requests[1].encoding == .gbk)
    #expect(requests[1].referer == "https://a.example")
    #expect(throws: SourceProblems("requests[0].method", "a source only sends GET")) {
      try DataSourceCheck.requests(from: Self.json(#"[{ "url": "https://a.example", "method": "POST" }]"#))
    }
    #expect(throws: SourceProblems("requests[0].url", "\"file:///etc/hosts\" is not an http(s) link")) {
      try DataSourceCheck.requests(from: Self.json(#"["file:///etc/hosts"]"#))
    }
  }

  @Test func tooManyRequestsAreRefused() {
    let many = JSONValue.array(Array(repeating: .string("https://a.example"), count: 21))

    #expect(throws: SourceProblems("requests", "returned 21; at most 20 in one fetch")) {
      try DataSourceCheck.requests(from: many)
    }
  }

  @Test func parseGivesRecordsOfNumbersTextPointsAndCandles() throws {
    let output = try DataSourceCheck.output(
      from: Self.json(
        """
        { "records": { "513100": { "price": 1.873, "name": "纳指", "day": [[1764000000000, 1.8], [1764000060000, 1.9]],
          "k": [[1764000000000, 1, 2, 0.5, 1.5]], "gone": null } }, "state": { "last": 3 } }
        """))

    let record = try #require(output.records["513100"])
    #expect(record["price"] == .number(1.873))
    #expect(record["name"] == .text("纳指"))
    #expect(
      record["day"]
        == .points([
          SourcePoint(at: Timestamp(millisecondsSince1970: 1_764_000_000_000), value: 1.8),
          SourcePoint(at: Timestamp(millisecondsSince1970: 1_764_000_060_000), value: 1.9),
        ]))
    #expect(
      record["k"]
        == .candles([
          SourceCandle(at: Timestamp(millisecondsSince1970: 1_764_000_000_000), open: 1, high: 2, low: 0.5, close: 1.5)
        ]))
    #expect(record["gone"] == nil)
    #expect(output.state == Self.json(#"{ "last": 3 }"#))
  }

  @Test func whatParseGivesInTheWrongShapeIsNamedWhereItIs() {
    #expect(throws: SourceProblems("parse", "did not return { records: { <record>: { <field>: value } } }")) {
      try DataSourceCheck.output(from: Self.json("[1]"))
    }
    #expect(
      throws: SourceProblems(all: [
        SourceProblem(#"records["a.b"]"#, "use only letters, digits, _ and - in a record's name"),
        SourceProblem(#"records["x"].bad"#, "is not a number, text, points or candles"),
      ])
    ) {
      try DataSourceCheck.output(from: Self.json(#"{ "records": { "x": { "bad": [[1, 2], [1, 2, 3]] }, "a.b": {} } }"#))
    }
  }

  @Test func aSnapshotThatFailsKeepsItsRecordsAndIsStale() {
    let got = SourceSnapshot(fetched: Timestamp(millisecondsSince1970: 1000), records: ["a": ["v": .number(1)]])
    let failed = got.failed(at: Timestamp(millisecondsSince1970: 2000)).failed(
      at: Timestamp(millisecondsSince1970: 3000))

    #expect(!got.isStale)
    #expect(failed.isStale)
    #expect(failed.failures == 2)
    #expect(failed.fetched == got.fetched)
    #expect(failed.records == got.records)
  }

  @Test func rowsReadNumbersFromTheirSourcesAndThePanelTimeIsTheOldest() throws {
    let readings = PanelReadings([
      SourceKey(.chat, "prem"): SourceSnapshot(
        fetched: Timestamp(millisecondsSince1970: 5000), records: ["513870": ["premium": .number(0.159)]]),
      SourceKey(.chat, "quote"): SourceSnapshot(
        fetched: Timestamp(millisecondsSince1970: 3000), failures: 1, records: ["513100": ["date": .number(20_261_123)]]
      ),
    ])
    let panel = Panel(name: "money", title: "投资", follow: "x", body: .rows(try PanelChartTests.rows()))

    #expect(readings.number(.field(SourceField("prem.513870.premium")!), of: .chat) == 0.159)
    #expect(readings.number(.field(SourceField("prem.159501.premium")!), of: .chat) == nil)
    #expect(readings.number(.fixed(2), of: .chat) == 2)
    #expect(readings.text(.field(SourceField("quote.513100.date")!), of: .chat) == "20261123")
    #expect(
      readings.time(of: panel, in: .chat)
        == PanelDataTime(fetched: Timestamp(millisecondsSince1970: 3000), stale: true))
    #expect(PanelReadings().time(of: panel, in: .chat) == nil)
  }

  @Test func aSpanIsCutFromTheNewestPointAndThinnedKeepingBothEnds() {
    let minute: Int64 = 60_000
    let points = (0..<3000).map {
      SourcePoint(at: Timestamp(millisecondsSince1970: Int64($0) * minute), value: Double($0))
    }

    let day = SourceHistory.cut(points, to: .day)

    #expect(day.count == SourceHistory.mostPoints)
    #expect(day.first?.value == Double(2999 - 1440))
    #expect(day.last?.value == 2999)
    #expect(SourceHistory.cut(Array(points.prefix(10)), to: .day).count == 10)
    #expect(SourceHistory.cut([], to: .year).isEmpty)
  }
}
