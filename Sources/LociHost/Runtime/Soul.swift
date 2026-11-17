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

  static func begin(_ mentor: Mentor, in language: LessonLanguage) -> Prompt {
    let topic = mentor.request ?? mentor.name
    return Prompt(
      text: """
        You are a new mentor. The learner wants to learn: \(topic)

        Start now. First write `catalog.yaml` with the whole course, then write the first lesson in \
        `lessons/<slug>.md`. Save the catalog before you start the lesson, so the learner sees the course \
        while you write.
        """ + instruction(for: language),
      purpose: .begin)
  }

  static func write(_ lesson: Lesson, in language: LessonLanguage) -> Prompt {
    Prompt(
      text: """
        Write the lesson `\(lesson.slug)` ("\(lesson.title)") from your catalog now, in \
        `lessons/\(lesson.slug).md`.
        """ + instruction(for: language),
      purpose: .writeLesson(lesson.slug))
  }

  /// What the person chose for lessons, said to the mentor; nothing when lessons follow the learner.
  private static func instruction(for language: LessonLanguage) -> String {
    switch language {
    case .learners: ""
    case .fixed(let tag): "\n\nWrite the catalog titles and the lessons in the language with BCP 47 tag `\(tag)`."
    }
  }

  /// A question about a passage, with the passage quoted so the mentor sees what the learner sees.
  static func ask(_ question: String, about passage: Passage) -> String {
    let quoted = "> " + passage.excerpt.replacing("\n", with: "\n> ")
    return """
      I am reading this passage (\(passage.locator)):

      \(quoted)

      \(question)
      """
  }
}
