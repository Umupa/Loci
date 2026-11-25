import Foundation
import Testing

@testable import LociModel

/// DS-S8–DS-S13: chart rows read from the JSON Loci writes, point at source fields, and are checked.
struct PanelChartTests {
  static let written = """
    {
      "title": "投资",
      "follow": "盯着持仓",
      "rows": [
        { "row": "quotes", "quotes": [
          { "name": "纳指100 QDII", "code": "513100", "price": "quote.513100.price",
            "change": "quote.513100.change", "spark": "quote.513100.day", "asOf": { "field": "quote.513100.date" },
            "digits": 3 } ] },
        { "row": "line", "value": "ndx.ndx.price", "change": "ndx.ndx.change", "series": "ndx.ndx.day",
          "digits": 0 },
        { "row": "ruler", "label": "市盈率 · 近五年分位", "value": 31.4, "share": 0.72, "low": 22.1, "high": 36.8,
          "digits": 1 },
        { "row": "allocation", "total": 61.8, "unit": "万", "change": -0.0091, "slices": [
          { "name": "纳指100", "actual": 0.58, "target": 0.6 }, { "name": "红利低波", "actual": 0.17, "target": 0.15 } ] },
        { "row": "heat", "tiles": [{ "code": "NVDA", "weight": 3, "change": -0.059 }] },
        { "row": "candles", "series": "kline.300308.daily", "lines": [
          { "name": "止盈", "price": 172, "kind": "take" }, { "name": "止损", "price": 138, "kind": "stop" } ] },
        { "row": "zones", "stops": [0, 0.03, 0.1, 0.2], "format": "percent", "values": [
          { "name": "513870", "note": "你持有", "value": "prem.513870.premium" } ] }
      ]
    }
    """

  static func rows(_ json: String = written) throws -> [PanelRow] {
    let panel = try PanelCheck.read(Data(json.utf8), name: "money")
    guard case .rows(let rows) = panel.body else { return [] }
    return rows
  }

  static func problems(_ row: String) -> [String] {
    do throws(PanelProblems) {
      _ = try PanelCheck.read(Data(#"{ "title": "a", "follow": "b", "rows": [\#(row)] }"#.utf8), name: "money")
      return []
    } catch {
      return error.all.map(\.description)
    }
  }

  @Test func chartRowsReadFromTheJSONLociWritesWithoutASentenceFirst() throws {
    let rows = try Self.rows()

    #expect(rows.count == 7)
    #expect(rows.allSatisfy { $0.isChart })
    guard case .quotes(let quotes) = rows[0], case .line(let line) = rows[1], case .zones(let zones) = rows[6] else {
      Issue.record("rows read as \(rows)")
      return
    }
    #expect(quotes[0].price == .field(SourceField("quote.513100.price")!))
    #expect(quotes[0].asOf == .field(SourceField("quote.513100.date")!))
    #expect(line.spans == PanelRange.allCases)
    #expect(line.style.digits == 0)
    #expect(zones.style.format == .percent)
  }

  @Test func chartRowsSurviveJSON() throws {
    let panel = Panel(name: "money", title: "投资", follow: "x", body: .rows(try Self.rows()))

    #expect(try HostCodingTests.roundTrips(panel))
  }

  @Test func aLineCanDrawADifferentFieldForEachSpan() throws {
    let rows = try Self.rows(
      #"{ "title": "a", "follow": "b", "rows": [{ "row": "line", "value": 1, "ranges": { "1d": "ndx.ndx.minutes", "5y": "ndx.ndx.days" } }] }"#
    )

    guard case .line(let line) = rows.first else {
      Issue.record("not a line: \(rows)")
      return
    }
    #expect(line.spans == [.day, .fiveYears])
    #expect(line.ranges[.fiveYears] == SourceField("ndx.ndx.days"))
  }

  @Test func aFieldWrittenWrongIsNamedWhereItIs() {
    #expect(
      Self.problems(#"{ "row": "zones", "stops": [0, 1], "values": [{ "name": "a", "value": "prem.513870" }] }"#)
        == [#"rows[0].values[0].value: "prem.513870" is not a number or <source>.<record>.<field>"#])
    #expect(
      Self.problems(#"{ "row": "candles", "series": "Kline" }"#)
        == [#"rows[0].series: "Kline" is not written <source>.<record>.<field>"#])
  }

  @Test func emptyChartsAndSharesOutOfRangeAreNamed() {
    #expect(Self.problems(#"{ "row": "quotes", "quotes": [] }"#) == ["rows[0].quotes: is empty"])
    #expect(
      Self.problems(#"{ "row": "ruler", "label": " ", "value": 1, "share": 1.5, "low": 0, "high": 2 }"#)
        == ["rows[0].label: is empty", "rows[0].share: 1.5 is not from 0 to 1"])
    #expect(
      Self.problems(#"{ "row": "heat", "tiles": [{ "code": "A", "weight": 0, "change": 0 }] }"#)
        == ["rows[0].tiles[0].weight: 0.0 is not more than 0"])
    #expect(
      Self.problems(#"{ "row": "zones", "stops": [0, 0.1, 0.05], "values": [] }"#)
        == ["rows[0].stops: must go up from the lowest to the highest", "rows[0].values: is empty"])
    #expect(
      Self.problems(#"{ "row": "allocation", "slices": [{ "name": "a", "actual": 2 }], "digits": 9 }"#)
        == ["rows[0].slices[0].actual: 2.0 is not from 0 to 1", "rows[0].digits: 9 is not from 0 to 6"])
  }

  @Test func aSpanOrKindThatIsNotOneIsNamedWithTheChoices() {
    #expect(
      Self.problems(#"{ "row": "candles", "series": "k.a.b", "lines": [{ "name": "x", "price": 1, "kind": "up" }] }"#)
        == ["rows[0].lines[0].kind: is not one of the values it can be: take, stop"])
  }

  @Test func aPanelOpeningWithWordsStillNeedsASentence() {
    #expect(
      Self.problems(#"{ "row": "label", "text": "x" }"#)
        == ["rows[0]: the first row must be a sentence that sums the panel up"])
  }

  @Test func aPanelKnowsTheSourcesItsRowsPointAt() throws {
    let panel = Panel(name: "money", title: "投资", follow: "x", body: .rows(try Self.rows()))

    #expect(
      panel.sources(of: .chat)
        == Set(["quote", "ndx", "kline", "prem"].map { SourceKey(.chat, $0) }))
  }
}
