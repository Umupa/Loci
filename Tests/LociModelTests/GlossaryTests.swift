import Testing

@testable import LociModel

struct GlossaryTests {
  static func glossary() throws -> Glossary {
    try Glossary(terms: [
      .init(term: "Pod", aliases: ["pods"], definition: "The smallest unit Kubernetes schedules."),
      .init(term: "调度器", definition: "决定任务放在哪台机器上的组件。", lesson: Lesson.Slug("scheduler")),
    ])
  }

  static func used(_ text: String, in lesson: Lesson.Slug? = nil) throws -> [String] {
    try glossary().firstUses(in: text, in: lesson).map { String(text[$0.range]) }
  }

  @Test func onlyTheFirstUseOfATermIsMarked() throws {
    let text = "调度器把 pod 放到节点上；调度器还会抢占。"

    #expect(try Self.used(text) == ["调度器", "pod"])
    #expect(try Self.glossary().firstUses(in: text).first?.range.lowerBound == text.startIndex)
  }

  @Test func anAliasCountsAsTheTerm() throws {
    #expect(try Self.used("Two Pods share a node.") == ["Pods"])
  }

  @Test func aLatinTermMatchesOnlyWholeWords() throws {
    #expect(try Self.used("A tripod is not a pod.") == ["pod"])
    #expect(try Self.used("podcast") == [])
  }

  @Test func theLessonThatTeachesATermDoesNotMarkIt() throws {
    #expect(try Self.used("调度器", in: Lesson.Slug("scheduler")) == [])
  }

  @Test func aNameUsedByTwoTermsIsRefused() {
    #expect(throws: ModelError.self) {
      try Glossary(terms: [
        .init(term: "Pod", definition: "a"), .init(term: "Container", aliases: ["pod"], definition: "b"),
      ])
    }
  }

  @Test func aDefinitionIsOneLine() {
    #expect(throws: ModelError.self) { try Glossary.Term(term: "Pod", definition: "one\ntwo") }
  }
}
