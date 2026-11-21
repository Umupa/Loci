import Foundation
import LociModel
import Testing

@testable import LociTool

/// P-S7: Loci writes panels with `loci panel`, and hears exactly what to fix when one cannot be shown.
struct PanelToolTests {
  static let valid = """
    { "title": "沙箱雷达", "follow": "盯着新版本", "refresh": { "every": "day", "at": "10:00" },
      "rows": [{ "row": "sentence", "text": "**v0.8.0** 发布。" }] }
    """
  static let panel = Panel(
    name: "radar", title: "沙箱雷达", follow: "盯着新版本", refresh: PanelRefresh(every: .day, at: "10:00"),
    body: .rows([.sentence("**v0.8.0** 发布。")]))

  private static func json(_ value: some Encodable) -> Data {
    (try? Failure.encoding(value)) ?? Data()
  }

  private func tool(_ line: ScriptedLine, input: String = "") -> Tool {
    var tool = Tool(line: line, folder: URL(filePath: "/loci/agent/")) { _ in "" }
    tool.readInput = { Data(input.utf8) }
    return tool
  }

  @Test func eachPanelVerbIsReadWithItsArguments() throws {
    #expect(try Request.parse(["panel", "save", "radar"]) == (.panel(.save("radar")), false))
    #expect(try Request.parse(["panel", "list"]) == (.panel(.list), false))
    #expect(try Request.parse(["panel", "show", "radar", "--json"]) == (.panel(.show("radar")), true))
  }

  @Test(arguments: [
    ["panel"], ["panel", "save"], ["panel", "save", "Radar"], ["panel", "list", "x"], ["panel", "drop", "x"],
  ])
  func aPanelCommandWrittenWrongSaysHowToWriteIt(arguments: [String]) {
    #expect(throws: UsageError.self) { try Request.parse(arguments) }
  }

  @Test func aPanelThatMakesSenseIsSavedUnderItsName() async {
    let line = ScriptedLine { _ in [.success(Self.json(Done()))] }

    let outcome = await tool(line, input: Self.valid).run(.panel(.save("radar")), json: false)

    #expect(outcome == .worked("Saved radar. It is beside the main conversation now, refreshed every day at 10:00."))
    #expect(line.requests == [.command(name: SavePanel.name, body: Self.json(SavePanel(Self.panel)))])
  }

  @Test func everyProblemIsPrintedAndNothingIsSent() async {
    let line = ScriptedLine { _ in [] }
    let input = """
      { "title": "", "follow": "x", "refresh": { "every": "week", "at": "10" },
        "rows": [{ "row": "label", "text": "a" }, { "row": "bars", "bars": [{ "name": "a", "fraction": 2, "value": "x" }] }] }
      """

    let outcome = await tool(line, input: input).run(.panel(.save("radar")), json: false)

    #expect(
      outcome
        == .failed(
          """
          The panel was not saved. Fix each of these and save it again:
          - title: is empty
          - refresh.at: "10" is not a time written HH:mm, such as 09:30
          - refresh.weekday: is missing; 1 is Sunday, 7 is Saturday
          - rows[0]: the first row must be a sentence that sums the panel up
          - rows[1].bars[0].fraction: 2.0 is not from 0 to 1
          """))
    #expect(line.requests.isEmpty)
  }

  @Test func whatTheAppRefusesIsPrintedAsItSaysIt() async {
    let line = ScriptedLine { _ in [.failure(.host(.invalidRequest("title: is empty")))] }

    let outcome = await tool(line, input: Self.valid).run(.panel(.save("radar")), json: false)

    #expect(outcome == .failed("title: is empty"))
  }

  @Test func listNamesEachPanelAndWhichFilesHaveProblems() async {
    let entries = [
      PanelEntry(name: "half", panel: nil, problems: [PanelProblem("", "is not JSON")]),
      PanelEntry(name: "radar", panel: Self.panel),
    ]
    let line = ScriptedLine { _ in [.success(Self.json(entries))] }

    let outcome = await tool(line).run(.panel(.list), json: false)

    #expect(
      outcome
        == .worked(
          "half  (cannot be shown)  — the file has 1 problem(s)\nradar  沙箱雷达, every day at 10:00"))
  }

  @Test func showPrintsThePanelAndWhatIsWrongWithItsFile() async throws {
    let entries = [PanelEntry(name: "radar", panel: Self.panel, problems: [PanelProblem("title", "is empty")])]
    let line = ScriptedLine { _ in [.success(Self.json(entries))] }

    let shown = await tool(line).run(.panel(.show("radar")), json: false)
    let missing = await tool(line).run(.panel(.show("other")), json: false)

    #expect(shown.status == 0)
    #expect(shown.text.contains(#""title" : "沙箱雷达""#))
    #expect(shown.text.hasSuffix("The file has problems. The panel shows what it last could:\n- title: is empty"))
    #expect(missing == .failed("There is no panel other. Run `loci panel list` to see them."))
  }
}
