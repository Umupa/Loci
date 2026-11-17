import AppKit
import LociModel
import Testing

@testable import LociUI

struct ReaderMarkTests {
  static func marked(_ marks: [ReaderMark], in text: ReadingText) -> [String] {
    marks.map { (text.plain as NSString).substring(with: $0.range) }
  }

  @Test func onlyParagraphsTheMentorChangedAreMarkedRevised() {
    let before = ReadingText(markdown: "# 过滤\n\n先排除不合适的节点。\n\n再打分。")
    let after = ReadingText(markdown: "# 过滤\n\n先排除资源不够的节点。\n\n再打分。\n\n最后绑定。")

    #expect(Self.marked(ReaderMark.revisions(from: before, to: after), in: after) == ["先排除资源不够的节点。", "最后绑定。"])
  }

  @Test func anUnchangedLessonHasNothingMarked() {
    let text = ReadingText(markdown: "# 过滤\n\n先排除不合适的节点。")

    #expect(ReaderMark.revisions(from: text, to: text).isEmpty)
  }

  @Test func termsAreMarkedWhereTheyAreFirstUsedInTheText() throws {
    let glossary = try Glossary(terms: [.init(term: "节点", definition: "一台能跑任务的机器。")])
    let text = ReadingText(markdown: "# 过滤\n\n先排除**不合适的节点**，再给节点打分。")
    let marks = ReaderMark.terms(of: glossary, in: text, lesson: nil)

    #expect(Self.marked(marks, in: text) == ["节点"])
    #expect(marks.first?.range.location == (text.plain as NSString).range(of: "节点").location)
  }
}
