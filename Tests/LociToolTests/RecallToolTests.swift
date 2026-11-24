import Foundation
import LociModel
import Testing

@testable import LociTool

/// ME-S5, ME-S9: `loci recall` finds what was said, and `loci help` holds every format a topic at a time.
struct RecallToolTests {
  private static func json(_ value: some Encodable) -> Data {
    (try? Failure.encoding(value)) ?? Data()
  }

  @Test func recallAndHelpAreReadWithTheirWords() throws {
    #expect(try Request.parse(["recall", "选主", "实验"]) == (.recall("选主 实验"), false))
    #expect(try Request.parse(["help", "memory"]) == (.help("memory"), false))
    #expect(throws: UsageError.self) { try Request.parse(["recall"]) }
    #expect(throws: UsageError.self) { try Request.parse(["help", "a", "b"]) }
  }

  @Test func recallPrintsEachFileWithTheWordsAroundTheMatch() async {
    let hit = RecallHit(path: "conversations/2025-11-17/main-x.md", day: Day("2025-11-17"), snippet: "…用 Raft 做过选主实验")
    let line = ScriptedLine { _ in [.success(Self.json([hit]))] }
    let tool = Tool(line: line, folder: URL(filePath: "/loci/agent/")) { _ in "" }

    let found = await tool.run(.recall("选主实验"), json: false)

    #expect(found == .worked("conversations/2025-11-17/main-x.md\n    …用 Raft 做过选主实验"))
  }

  @Test func helpGivesOneTopicOrSaysWhichThereAre() {
    #expect(Tool.help("memory") == .worked(ToolGuide.topic("memory") ?? ""))
    #expect(Tool.help(nil) == .worked(ToolGuide.text))
    #expect(Tool.help("cooking").status == 1)
  }
}
