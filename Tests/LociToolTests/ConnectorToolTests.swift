import Foundation
import LociModel
import Testing

@testable import LociTool

/// CN-S3: the companion lists its connectors and reads with them through `loci connector`.
struct ConnectorToolTests {
  static let notion = Connector(
    id: ConnectorID("notion"), name: "Notion", source: .mcp, server: URL(string: "https://mcp.notion.com/mcp")!,
    account: "Umi",
    status: .ready,
    tools: [
      ConnectorTool(name: "search", description: "Search pages\nand databases", inputSchema: #"{"type":"object"}"#)
    ],
    connectedAt: Timestamp(millisecondsSince1970: 0), readsToday: 0, lastUsed: nil)

  private static func json(_ value: some Encodable) -> Data {
    (try? Failure.encoding(value)) ?? Data()
  }

  private func tool(_ line: ScriptedLine) -> Tool {
    Tool(line: line, folder: URL(filePath: "/loci/agent/")) { _ in "" }
  }

  @Test func listAndCallAreReadWithTheirArguments() throws {
    #expect(try Request.parse(["connector", "list"]) == (.connector(.list(nil)), false))
    #expect(try Request.parse(["connector", "list", "notion"]) == (.connector(.list(ConnectorID("notion"))), false))
    #expect(
      try Request.parse(["connector", "call", "notion", "search", #"{"query": "周会"}"#])
        == (.connector(.call(ConnectorID("notion"), tool: "search", arguments: #"{"query": "周会"}"#)), false))
    #expect(
      try Request.parse(["connector", "call", "notion", "search"])
        == (.connector(.call(ConnectorID("notion"), tool: "search", arguments: "{}")), false))
  }

  /// CN-S15: `loci connector call gh …` is GitHub's `gh` tool with the words as they were typed.
  @Test func ghIsShortForGitHubsGhToolWithTheWordsAsGiven() throws {
    guard
      case (.connector(.call(let connector, let tool, let arguments)), false) = try Request.parse(
        ["connector", "call", "gh", "run", "view", "123", "--log", "-R", "o/r"])
    else { throw UsageError("not a call") }
    #expect(connector == ConnectorID("github") && tool == "gh")
    let words = try JSONDecoder().decode([String: [String]].self, from: Data(arguments.utf8))["args"]
    #expect(words == ["run", "view", "123", "--log", "-R", "o/r"])
  }

  @Test(arguments: [
    ["connector"], ["connector", "call", "notion"], ["connector", "call", "notion", "search", "周会"],
    ["connector", "call", "notion", "search", "[1]"], ["connector", "drop", "notion"],
  ])
  func aConnectorCommandWrittenWrongSaysHowToWriteIt(_ words: [String]) {
    #expect(throws: UsageError.self) { try Request.parse(words) }
  }

  @Test func listPrintsEachConnectorWithItsReadableToolsOrWhyItCannotRead() async {
    let waiting = Connector(
      id: ConnectorID("linear"), name: "Linear", source: .mcp, server: URL(string: "https://mcp.linear.app/mcp")!,
      account: nil,
      status: .needsReconnecting("the sign-in ran out"), tools: [], connectedAt: Timestamp(millisecondsSince1970: 0),
      readsToday: 0, lastUsed: nil)
    let line = ScriptedLine { _ in [.success(Self.json([Self.notion, waiting]))] }

    let all = await tool(line).run(.connector(.list(nil)), json: false)
    let one = await tool(line).run(.connector(.list(ConnectorID("notion"))), json: false)

    #expect(
      all
        == .worked(
          "notion  Notion, Umi\n    search  Search pages\n\n"
            + "linear  Linear\n    needs reconnecting (the sign-in ran out); the person reconnects it on the Connectors page"
        ))
    #expect(one == .worked("notion  Notion, Umi\n\nsearch\n  Search pages\n  arguments: {\"type\":\"object\"}"))
  }

  @Test func aCallPrintsWhatTheAppGaveBackAsItIs() async {
    let marked = "<external-content connector=\"notion\" tool=\"search\">\n周会纪要\n</external-content>"
    let line = ScriptedLine { _ in [.success(Self.json(marked))] }

    let outcome = await tool(line).run(
      .connector(.call(ConnectorID("notion"), tool: "search", arguments: "{}")), json: false)

    #expect(outcome == .worked(marked))
    #expect(
      line.requests
        == [.command(name: CallConnector.name, body: Self.json(CallConnector(ConnectorID("notion"), tool: "search")))])
  }
}
