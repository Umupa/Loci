import Foundation
import LociModel

/// The instructions a mentor's agent works under, and the prompts Loci writes for the person.
enum Soul {
  /// The Mentor template with the person's sentence filled in. The templates are part of the app, so a
  /// missing one is a broken build, reported as a failed turn rather than a crash.
  static func text(for mentor: Mentor) throws(HostError) -> String {
    guard let url = Bundle.module.url(forResource: "mentor", withExtension: "md", subdirectory: "Resources/Souls"),
      let template = try? String(contentsOf: url, encoding: .utf8)
    else { throw .storage("the mentor template is missing from the app") }
    return template.replacing("{{topic}}", with: mentor.request ?? mentor.name)
  }

  static func begin(_ mentor: Mentor) -> Prompt {
    let topic = mentor.request ?? mentor.name
    return Prompt(
      text: """
        You are a new mentor. The learner wants to learn: \(topic)

        Start now. First write `catalog.yaml` with the whole course, then write the first lesson in \
        `lessons/<slug>.md`. Save the catalog before you start the lesson, so the learner sees the course \
        while you write.
        """,
      purpose: .begin)
  }

  static func write(_ lesson: Lesson) -> Prompt {
    Prompt(
      text: """
        Write the lesson `\(lesson.slug)` ("\(lesson.title)") from your catalog now, in \
        `lessons/\(lesson.slug).md`.
        """,
      purpose: .writeLesson(lesson.slug))
  }

  static func question(_ question: String, about locator: Locator, excerpt: String?) -> String {
    let passage = excerpt.map { "\n\n> " + $0.replacing("\n", with: "\n> ") } ?? ""
    return """
      The learner is reading and asks about this passage (\(locator)):\(passage)

      \(question)

      Answer in the language of the question, directly and briefly: the answer is shown beside the passage. \
      Do not change any files.
      """
  }
}
