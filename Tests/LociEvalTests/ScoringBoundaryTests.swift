import Foundation
import LociModel
import Testing

@testable import LociEval

struct ScoringBoundaryTests {
  @Test(arguments: [
    "https://github.com/kubernetes-else/project",
    "https://github.com/kubernetes.evil/project",
    "https://github.com/kubernetes%2Delse/project",
  ])
  func aSimilarRepositoryNameIsNotAFirstPartySource(_ link: String) {
    #expect(!Checks.isFirstParty(link, ["github.com/kubernetes"]))
  }

  @Test(arguments: [
    "https://github.com/kubernetes", "https://github.com/kubernetes/",
    "https://github.com/kubernetes/kubernetes?tab=readme", "https://GITHUB.COM/kubernetes/kubernetes",
  ])
  func aFirstPartyRepositoryAndItsChildrenCount(_ link: String) {
    #expect(Checks.isFirstParty(link, ["github.com/kubernetes"]))
  }

  @Test(arguments: ["https://kubernetes.io.evil.org/docs", "https://kubernetes.io@evil.org/docs", "not a URL"])
  func aLookalikeHostDoesNotCountAsFirstParty(_ link: String) {
    #expect(!Checks.isFirstParty(link, ["kubernetes.io"]))
  }

  @Test func missingEvidenceDoesNotEarnAutomaticCredit() {
    let checks = Checks(
      Evidence(
        scenario: Scenario.all[0], catalog: nil, lessons: [], conversation: [], catalogAfter: nil,
        firstLessonAfter: nil, stoppedFirstTurn: true, probeAnswer: " \n\t"))

    #expect(checks.plannedLessons == 0)
    #expect(checks.writtenLessons == 0)
    #expect(!checks.lessonsInRange)
    #expect(checks.links == 0)
    #expect(checks.firstPartyLinks == 0)
    #expect(checks.locators == 0)
    #expect(checks.catalogAfterSeconds == nil)
    #expect(checks.firstLessonAfterSeconds == nil)
    #expect(checks.stoppedFirstTurn)
    #expect(!checks.probeAnswered)
  }

  @Test(arguments: [3, 4, 20, 21])
  func theCatalogLessonRangeIncludesBothEndpoints(_ count: Int) throws {
    let lessons = try (0..<count).map { try Lesson(slug: Lesson.Slug("lesson-\($0)")!, title: "Lesson \($0)") }
    let scenario = Scenario.all[0]
    let catalog = try Catalog(chapters: [Catalog.Chapter(title: "Course", lessons: lessons)])
    let checks = Checks(
      Evidence(
        scenario: scenario, catalog: catalog, lessons: [], conversation: [], catalogAfter: 12.5,
        firstLessonAfter: 60.25, stoppedFirstTurn: false, probeAnswer: "Answer"))

    #expect(checks.lessonsInRange == scenario.lessons.contains(count))
    #expect(checks.plannedLessons == count)
    #expect(checks.writtenLessons == 0)
    #expect(checks.catalogAfterSeconds == 12.5)
    #expect(checks.firstLessonAfterSeconds == 60.25)
    #expect(checks.probeAnswered)
  }

  @Test func interruptedTurnsAreNotCountedAsAgentFailures() {
    let messages = [Message(id: EntityID(), at: Timestamp(millisecondsSince1970: 0), body: .ended(.interrupted))]
    let checks = Checks(
      Evidence(
        scenario: Scenario.all[0], catalog: nil, lessons: [], conversation: messages, catalogAfter: nil,
        firstLessonAfter: nil, stoppedFirstTurn: true, probeAnswer: ""))
    #expect(checks.failedTurns == 0)
  }

  @Test func unknownRubricItemsDoNotChangeTheMean() throws {
    let verdict = try #require(
      Verdict(
        reply:
          #"{"scores":{"firstHand":{"score":1,"reason":"sources"},"readability":{"score":4,"reason":"clear"},"extra":{"score":100,"reason":"ignored"}}}"#
      ))
    #expect(verdict.mean == 2.5)
    #expect(verdict.worst == nil)
  }

  @Test(arguments: ["{}", #"{"scores":"wrong"}"#, #"{"scores":{"firstHand":{"score":"five","reason":""}}}"#])
  func aMalformedVerdictIsRefused(_ reply: String) {
    #expect(Verdict(reply: reply) == nil)
  }

  @Test func lessonBodyLinksStopAtMarkdownDelimiters() {
    #expect(
      Checks.links(in: "[source](https://kubernetes.io/docs) <http://sqlite.org/wal> `https://github.com/x` ") == [
        "https://kubernetes.io/docs", "http://sqlite.org/wal", "https://github.com/x",
      ])
  }
}
