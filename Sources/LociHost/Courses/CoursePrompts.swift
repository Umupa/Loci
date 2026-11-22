import Foundation
import LociModel
import LociStore

extension AgentContext {
  func coursePrompt(_ active: CourseWork.Active, in page: CoursePage) -> (Prompt, String) {
    let course = page.course
    let prompt: Prompt
    let text: String
    switch active.request {
    case .message(let message, let saying, let lesson):
      prompt = message
      if let lesson {
        let title = course.lessons.first { $0.id == lesson }?.title ?? lesson.description
        text = "The person is reading the lesson \"\(title)\" (ID: \(lesson)).\n\n" + saying
      } else {
        text = saying
      }
    case .event(let event):
      let words = event.words
      let lessonTitle: String?
      if case .writeLesson(let lesson, let reason) = event {
        lessonTitle = reason == .requested ? course.lessons.first { $0.id == lesson }?.title : nil
        let path = store.courseDraftPath(course.id, turn: active.id, lesson: lesson)
        text =
          words.instruction + "\n\nWrite this lesson's draft in `\(path)`. Create its parent directories. "
          + "Save completed paragraphs to that file as you write. When it is complete, run "
          + "`\"$LOCI\" lesson write \(lesson) \(path)`."
      } else {
        lessonTitle = nil
        text = words.instruction
      }
      prompt = Prompt(text: words.display, purpose: .course(event), lessonTitle: lessonTitle)
    }
    return (prompt, text)
  }

  /// The course's instructions when its session opens, and the course as it is now.
  func courseBriefing(_ course: EntityID, opening: Bool) -> [String] {
    (opening ? ["\n" + prompts.course + "\n"] : []) + [details(of: course)].compactMap(\.self)
  }

  /// A course's session gets a `loci` that reaches only that course, with an access that is new each time it opens.
  func tool(for owner: SessionOwner, else other: LocalSession?) -> LocalSession? {
    guard case .conversation(.course(let course)) = owner else { return other }
    return .course(course, access: environment.newID())
  }

  func details(of course: EntityID) -> String? {
    guard let page = try? store.coursePage(course) else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(page.course) else { return nil }
    let written = page.lessons.filter { $0.body == .written }.map { $0.id.description }.joined(separator: ", ")
    return """
      \n<loci-course>
      This session belongs to the course at ../courses/\(course)/. Read finished Markdown in lessons/ and
      highlights in notes/ there. Use the course tools to change the course. The following is its current data.
      Lessons with finished Markdown: \(written)

      \(String(decoding: data, as: UTF8.self))
      </loci-course>
      \n
      """
  }
}

extension CourseEvent {
  private var sourceInstruction: String {
    switch self {
    case .addedSource(let source):
      "The person added this source: \(source.url.absoluteString) (\(source.id)). Include it."
    case .removedSource(let source): "The person removed this source: \(source.url.absoluteString). Leave it out."
    default: ""
    }
  }

  fileprivate var words: (display: String, instruction: String) {
    switch self {
    case .started(let topic):
      (topic, "The person wants to learn: \(topic). Start the goal interview and publish the first follow-up.")
    case .answered(let question, let answers):
      (
        answers.joined(separator: " · "),
        "The person answered \"\(question)\": \(answers.joined(separator: " · ")). Update the goal and continue."
      )
    case .confirmedGoal:
      ("Yes, that's right", "The person confirmed the goal. Set its subtitle and length and mark it ready.")
    case .askedToReviseGoal:
      ("Let's change it", "The person wants to revise the goal. Ask what they would like to change.")
    case .beganSources:
      ("Find sources", "The person chose to start gathering first-hand sources. Find them and record each one.")
    case .addedSource, .removedSource:
      (sourceInstruction, sourceInstruction)
    case .beganWriting:
      (
        "Start writing",
        "The person chose to start writing. Plan the whole course with loci course plan. "
          + "Finish this turn after saving the plan. The app will ask for the first three lessons, one at a time."
      )
    case .writeLesson(let lesson, let reason):
      switch reason {
      case .firstLessons:
        ("Write \(lesson)", "Write the initial lesson \(lesson). Finish only this lesson in this turn.")
      case .openedLastWritten:
        ("Continue writing", "The person opened the last written lesson. Write the next lesson, \(lesson).")
      case .requested:
        ("Write \(lesson) now", "The person asked to write lesson \(lesson) now. Write that lesson in this turn.")
      }
    }
  }
}
