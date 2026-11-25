import Foundation
import LociModel
import Testing

@testable import LociTool

/// DS-S1, DS-S6: Loci writes a source with `loci source`, hears what it got, and tries a fix on the samples.
struct SourceToolTests {
  static let script = "function requests() { return ['https://qt.gtimg.cn/q=sh513870']; }\nfunction parse() {}"
  static let source = DataSource(
    name: "prem", title: "ETF 溢价", every: SourceEvery(minutes: 1)!, window: SourceWindow("09:30-15:00", weekdays: true),
    script: script)

  private static func json(_ value: some Encodable) -> Data {
    (try? Failure.encoding(value)) ?? Data()
  }

  private func tool(_ line: ScriptedLine, input: String = "") -> Tool {
    var tool = Tool(line: line, folder: URL(filePath: "/loci/agent/")) { _ in "" }
    tool.readInput = { Data(input.utf8) }
    tool.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
    return tool
  }

  @Test func eachSourceVerbIsReadWithItsArguments() throws {
    #expect(
      try Request.parse([
        "source", "save", "prem", "--title", "ETF 溢价", "--every", "1m", "--between", "09:30-15:00", "--weekdays",
      ])
        == (
          .source(
            .save(
              name: "prem", title: "ETF 溢价", every: SourceEvery(minutes: 1)!,
              window: SourceWindow("09:30-15:00", weekdays: true))), false
        ))
    #expect(
      try Request.parse(["source", "test", "prem", "--script"]) == (.source(.test("prem", newScript: true)), false))
    #expect(try Request.parse(["source", "test", "prem"]) == (.source(.test("prem", newScript: false)), false))
    #expect(try Request.parse(["source", "show", "prem", "--json"]) == (.source(.show("prem")), true))
    #expect(try Request.parse(["source", "list"]) == (.source(.list), false))
  }

  @Test(arguments: [
    ["source"], ["source", "save", "prem"], ["source", "save", "prem", "--title", "x"],
    ["source", "save", "prem", "--title", "x", "--every", "5s"],
    ["source", "save", "Prem", "--title", "x", "--every", "1m"],
    ["source", "save", "prem", "--title", "x", "--every", "1m", "--weekdays"],
    ["source", "save", "prem", "--title", "x", "--every", "1m", "--between", "15:00-09:30"],
    ["source", "show"], ["source", "drop", "prem"],
  ])
  func aSourceCommandWrittenWrongSaysHowToWriteIt(arguments: [String]) {
    #expect(throws: UsageError.self) { try Request.parse(arguments) }
  }

  @Test func aSavedSourceSaysWhatTheFetchGotAndHowToPointAtIt() async {
    let records: [String: SourceRecord] = ["513870": ["premium": .number(0.159), "name": .text("纳指ETF")]]
    let line = ScriptedLine { _ in [.success(Self.json(SourceOutcome.records(records)))] }

    let outcome = await tool(line, input: Self.script).run(
      .source(
        .save(
          name: "prem", title: "ETF 溢价", every: SourceEvery(minutes: 1)!,
          window: SourceWindow("09:30-15:00", weekdays: true))),
      json: false)

    #expect(
      outcome
        == .worked(
          """
          Saved prem. It is fetched every 1m between 09:30-15:00 on weekdays. This fetch got:
            prem.513870: name="纳指ETF", premium=0.159
          Point panel rows at prem.<record>.<field>.
          """))
    #expect(line.requests == [.command(name: SaveDataSource.name, body: Self.json(SaveDataSource(Self.source)))])
  }

  @Test func aSourceThatFailsIsNotSavedAndEveryProblemIsPrinted() async {
    let line = ScriptedLine { _ in
      [.success(Self.json(SourceOutcome.failed(SourceProblems("requests[0]", "https://a.example: HTTP 404"))))]
    }

    let outcome = await tool(line, input: Self.script).run(
      .source(.save(name: "prem", title: "x", every: SourceEvery(minutes: 1)!, window: nil)), json: false)

    #expect(
      outcome
        == .failed(
          """
          The source was not saved. Fix each of these and save it again:
          - requests[0]: https://a.example: HTTP 404
          """))
  }

  @Test func anEmptyScriptIsRefusedWithoutAskingTheApp() async {
    let line = ScriptedLine { _ in [] }

    let outcome = await tool(line, input: "  ").run(
      .source(.save(name: "prem", title: "x", every: SourceEvery(minutes: 1)!, window: nil)), json: false)

    #expect(outcome.status == 1)
    #expect(line.requests.isEmpty)
  }

  @Test func testingANewScriptPrintsWhatEachSampleGives() async {
    let replays = [
      SourceReplay(
        at: Timestamp(millisecondsSince1970: 1_763_337_600_123),
        outcome: .records(["513870": ["premium": .number(0.16)]])),
      SourceReplay(
        at: Timestamp(millisecondsSince1970: 1_763_337_540_123),
        outcome: .failed(SourceProblems("script", "x is not defined"))),
    ]
    let line = ScriptedLine { _ in [.success(Self.json(replays))] }

    let outcome = await tool(line, input: "function parse() {}").run(
      .source(.test("prem", newScript: true)), json: false)

    #expect(
      outcome
        == .failed(
          """
          Sample from 2025-11-17 08:00:
            513870: premium=0.16

          Sample from 2025-11-17 07:59 failed:
          - script: x is not defined
          """))
    #expect(
      line.requests == [
        .command(name: TestDataSource.name, body: Self.json(TestDataSource("prem", script: "function parse() {}")))
      ])
  }

  @Test func listSaysWhenEachSourceLastGotSomethingAndWhetherItIsFailing() async {
    let entries = [
      DataSourceEntry(
        source: Self.source,
        snapshot: SourceSnapshot(
          fetched: Timestamp(millisecondsSince1970: 1_763_337_600_123), failures: 2, records: [:]),
        samples: 3),
      DataSourceEntry(
        source: DataSource(name: "nav", title: "净值", every: SourceEvery(minutes: 60)!, script: "x"), snapshot: nil,
        samples: 0),
    ]
    let line = ScriptedLine { _ in [.success(Self.json(entries))] }

    let outcome = await tool(line).run(.source(.list), json: false)

    #expect(
      outcome
        == .worked(
          """
          prem  ETF 溢价, every 1m  got 2025-11-17 08:00, failed 2 time(s) since
          nav  净值, every 1h  never fetched
          """))
  }
}
