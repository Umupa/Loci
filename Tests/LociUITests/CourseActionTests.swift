import Foundation
import LociModel
import Testing

@testable import LociUI

struct CourseActionTests {
  @Test(
    "Course action bubbles use the interface language and keep the reader's own words", arguments: ["zh-Hans", "en"])
  func showsCourseActionsInTheInterfaceLanguage(tag: String) throws {
    let locale = Locale(identifier: tag)
    let words = try CourseActionSamples.prompts().map { $0.bubbleText(in: locale) }
    let expected =
      if tag == "en" {
        [
          "Raft", "For work · Read the paper", "My own words", "Yes, that's right", "Change it", "Find sources",
          "https://raft.github.io/", "Remove: The Raft paper", "Start writing", "Write it now: Raft at a glance",
        ]
      } else {
        [
          "Raft", "For work · Read the paper", "My own words", "对，就这样", "改一下", "去找资料",
          "https://raft.github.io/", "移除：The Raft paper", "开始写", "现在写：Raft at a glance",
        ]
      }
    #expect(words == expected)
  }

  @Test("Previously recorded writing requests show the lesson title when it is still in the course")
  func readsOlderWritingRequests() throws {
    let id = try #require(Lesson.ID("raft-map"))
    let legacy = Prompt(text: "Write raft-map now", purpose: .course(.writeLesson(id, reason: .requested)))
    let lesson = try Lesson(id: id, title: "Raft at a glance")
    let locale = Locale(identifier: "zh-Hans")
    #expect(legacy.bubbleText(in: locale, courseLessons: [lesson]) == "现在写：Raft at a glance")
    #expect(legacy.bubbleText(in: locale) == "现在写")
  }

  @Test("An ordinary course chat keeps the text the reader typed")
  func chatIsVerbatim() {
    let prompt = Prompt(text: "Start writing", purpose: .chat)
    #expect(prompt.bubbleText(in: Locale(identifier: "zh-Hans")) == "Start writing")
  }
}

enum CourseActionSamples {
  static func prompts() throws -> [Prompt] {
    let link = try #require(URL(string: "https://raft.github.io/"))
    let source = try CourseSource(id: EntityID(), from: CourseSource.Draft(url: link, title: "The Raft paper"))
    let lesson = try #require(Lesson.ID("raft-map"))
    return [
      Prompt(text: "Raft", purpose: .course(.started(topic: "Raft"))),
      Prompt(text: "For work", purpose: .course(.answered(question: "Why?", answers: ["For work", "Read the paper"]))),
      Prompt(text: "My own words", purpose: .course(.answered(question: "Why?", answers: ["My own words"]))),
      Prompt(text: "Yes, that's right", purpose: .course(.confirmedGoal)),
      Prompt(text: "Let's change it", purpose: .course(.askedToReviseGoal)),
      Prompt(text: "Find sources", purpose: .course(.beganSources)),
      Prompt(text: "The person added \(source.id). Include it.", purpose: .course(.addedSource(source))),
      Prompt(text: "Remove \(source.id). Leave it out.", purpose: .course(.removedSource(source))),
      Prompt(text: "Start writing", purpose: .course(.beganWriting)),
      Prompt(
        text: "Write raft-map now", purpose: .course(.writeLesson(lesson, reason: .requested)),
        lessonTitle: "Raft at a glance"),
    ]
  }
}
