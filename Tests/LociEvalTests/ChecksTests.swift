import Foundation
import LociModel
import Testing

@testable import LociEval

struct ChecksTests {
  private let scenario = Scenario.all[0]

  private func evidence(catalog: Int, lessons: [Evidence.WrittenLesson], conversation: [Message] = []) throws
    -> Evidence
  {
    let planned = try (0..<catalog).map { try Lesson(slug: Lesson.Slug("l\($0)")!, title: "Lesson \($0)") }
    return Evidence(
      scenario: scenario, catalog: try Catalog(chapters: [try Catalog.Chapter(title: "One", lessons: planned)]),
      lessons: lessons, conversation: conversation, catalogAfter: 30, firstLessonAfter: 90, stoppedFirstTurn: false,
      probeAnswer: "PreFilter runs first.")
  }

  @Test func linksOnTheScenariosOwnSitesCountAsFirstParty() throws {
    let lesson = Evidence.WrittenLesson(
      slug: "l0", title: "Lesson 0",
      sources: ["https://kubernetes.io/docs/concepts/scheduling", "019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f"],
      body: "See https://github.com/kubernetes/enhancements/kep and https://medium.com/some-post, and "
        + "[this](loci://library/019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f#quote=Filter).")

    let checks = Checks(try evidence(catalog: 6, lessons: [lesson]))

    #expect(checks.plannedLessons == 6)
    #expect(checks.writtenLessons == 1)
    #expect(checks.lessonsInRange)
    #expect(checks.links == 3)
    #expect(checks.firstPartyLinks == 2)
    #expect(checks.locators == 1)
    #expect(checks.probeAnswered)
  }

  @Test func aSiteGivenWithAPathOnlyMatchesUnderThatPath() {
    #expect(Checks.isFirstParty("https://github.com/kubernetes/kubernetes", ["github.com/kubernetes"]))
    #expect(!Checks.isFirstParty("https://github.com/someone/kubernetes", ["github.com/kubernetes"]))
    #expect(Checks.isFirstParty("https://www.sqlite.org/wal.html", ["sqlite.org"]))
    #expect(!Checks.isFirstParty("https://notsqlite.org/wal.html", ["sqlite.org"]))
  }

  @Test func failedTurnsAndPermissionAsksAreCounted() throws {
    let at = Timestamp(millisecondsSince1970: 0)
    let conversation = [
      Message(id: EntityID(), at: at, body: .ended(.failed("quota"))),
      Message(
        id: EntityID(), at: at,
        body: .permission(PermissionAsk(id: "1", title: "bash", tool: nil, options: [], answer: .dismissed))),
    ]
    let checks = Checks(try evidence(catalog: 30, lessons: [], conversation: conversation))

    #expect(!checks.lessonsInRange)
    #expect(checks.failedTurns == 1)
    #expect(checks.permissionAsks == 1)
  }
}

struct VerdictTests {
  @Test func theVerdictIsFoundAmongTheJudgesWords() throws {
    let reply = """
      Here is my verdict:
      {"scores": {"firstHand": {"score": 4, "reason": "cites KEPs"}, "courseStructure": {"score": 5, "reason": "map"},
      "grounding": {"score": 3, "reason": "few quotes"}, "firstTenMinutes": {"score": 5, "reason": "fast"},
      "firstPrinciples": {"score": 4, "reason": "why first"}, "readability": {"score": 3, "reason": "jargon"}},
      "worst": "Quote the sources."}
      """
    let verdict = try #require(Verdict(reply: reply))

    #expect(verdict.mean == 4)
    #expect(verdict.worst == "Quote the sources.")
    #expect(Verdict(reply: "no json here") == nil)
  }
}

struct FrontMatterTests {
  @Test func sourcesAreReadFromTheFrontMatter() {
    let text = """
      ---
      sources:
      - https://kubernetes.io/docs/
      - '019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f'
      title: ignored
      ---
      - not a source
      """
    #expect(FrontMatter.sources(in: text) == ["https://kubernetes.io/docs/", "019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f"])
    #expect(FrontMatter.sources(in: "# No front matter").isEmpty)
  }

  @Test func unknownOptionsAreRefused() {
    #expect(throws: EvalError.self) { try Options(["--scenario", "nope"]) }
    #expect(throws: EvalError.self) { try Options(["--fast"]) }
    #expect((try? Options(["--scenario", "sqlite-wal", "--no-judge"]))?.scenarios.map(\.id) == ["sqlite-wal"])
  }
}
