import Foundation
import LociModel
import Testing

@testable import LociTool

struct CourseToolTests {
  @Test("Course tools parse the documented verbs without accepting a course ID")
  func parsesScopedCommands() throws {
    #expect(try Request.parse(["course", "ask"]).request == .course(.ask))
    #expect(try Request.parse(["course", "goal"]).request == .course(.goal))
    #expect(try Request.parse(["course", "ready"]).request == .course(.ready))
    #expect(try Request.parse(["course", "plan"]).request == .course(.plan))
    #expect(try Request.parse(["course", "source", "list"]).request == .course(.listSources))
    let lesson = try #require(Lesson.ID("quorum"))
    #expect(try Request.parse(["lesson", "write", "quorum", "a.md"]).request == .course(.writeLesson(lesson, "a.md")))
    #expect(throws: UsageError.self) { try Request.parse(["course", "plan", "other-course"]) }
    #expect(throws: UsageError.self) { try Request.parse(["lesson", "write", "../wrong", "a.md"]) }
    #expect(throws: UsageError.self) {
      try Request.parse(["course", "source", "add", "https://example.org", "--kind", "repository"])
    }
  }

  @Test("Malformed questions or plans exit with status two before contacting the host")
  func invalidJSONExplainsTheFix() async {
    let line = ScriptedLine { _ in [] }
    let ask = await tool(line, input: #"{"question":"Why?","options":[],"multiple":false}"#)
      .run(.course(.ask), json: false)
    #expect(ask.status == 2)
    #expect(ask.text.contains("2 to 4"))
    let plan = await tool(line, input: #"{"title":"wrong shape"}"#).run(.course(.plan), json: false)
    #expect(plan.status == 2)
    #expect(plan.text.contains("loci course plan"))
    #expect(line.requests.isEmpty)
  }

  @Test("A lesson send contains its Markdown and its lesson ID")
  func readsTheFile() async throws {
    let line = ScriptedLine { _ in [.success(Data("{}".utf8))] }
    let lesson = try #require(Lesson.ID("quorum"))
    let result = await tool(line).run(.course(.writeLesson(lesson, "a.md")), json: false)
    #expect(result.status == 0)
    #expect(line.requests == [.course(.writeLesson(lesson, markdown: "A quorum holds."))])
  }

  @Test("The course tool prints structured sources and preserves scope and usage exit status")
  func printsSourcesAndErrors() async throws {
    let url = try #require(URL(string: "https://example.org/paper.pdf"))
    let source = try CourseSource(id: EntityID(), from: CourseSource.Draft(url: url, title: "The paper"))
    let encoded = try JSONEncoder().encode([source])
    let line = ScriptedLine { _ in [.success(encoded)] }
    let plain = await tool(line).run(.course(.listSources), json: false)
    #expect(plain.text.contains(source.id.description) && plain.text.contains("The paper"))
    let json = await tool(line).run(.course(.listSources), json: true)
    #expect(try JSONDecoder().decode([CourseSource].self, from: Data(json.text.utf8)) == [source])
    let wrong = ScriptedLine { _ in [.failure(.host(.invalidRequest("Keep the finished lesson.")))] }
    let wrongResult = await tool(wrong, input: "[]").run(.course(.plan), json: false)
    #expect(wrongResult == Tool.Outcome(text: "Keep the finished lesson.", status: 2))
    let outside = ScriptedLine { _ in [.failure(.host(.invalidRequest(CourseToolRequest.scopeMessage)))] }
    let outsideResult = await tool(outside).run(.course(.ready), json: false)
    #expect(outsideResult == .failed(CourseToolRequest.scopeMessage))
  }

  private func tool(_ line: ScriptedLine, input: String = "") -> Tool {
    var tool = Tool(line: line, folder: URL(filePath: "/loci/agent/")) { _ in "A quorum holds." }
    tool.readInput = { Data(input.utf8) }
    return tool
  }
}
