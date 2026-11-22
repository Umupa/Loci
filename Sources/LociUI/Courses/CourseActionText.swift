import Foundation
import LociModel

extension Prompt {
  var showsPersonBubble: Bool {
    if case .course(.writeLesson(_, let reason)) = purpose { return reason == .requested }
    if case .course(.drawAtlas) = purpose { return false }
    return true
  }

  func bubbleText(in locale: Locale, courseLessons: [Lesson] = []) -> String {
    guard case .course(let event) = purpose else { return text }
    var label: LocalizedStringResource
    switch event {
    case .started(let topic): return topic
    case .answered(_, let answers): return answers.joined(separator: " · ")
    case .confirmedGoal: label = .loci("course.confirmGoal")
    case .askedToReviseGoal: label = .loci("course.reviseGoal")
    case .beganSources: label = CourseStage.goal.next
    case .addedSource(let source): return source.url.absoluteString
    case .removedSource(let source): label = .loci("course.struckSource \(source.title)")
    case .beganWriting: label = CourseStage.sources.next
    case .drawAtlas: label = .loci("course.atlas")
    case .writeLesson(let id, _):
      let title = lessonTitle ?? courseLessons.first { $0.id == id }?.title
      if let title {
        label = .loci("course.writeLessonNow \(title)")
      } else {
        label = .loci("course.writeNow")
      }
    }
    label.locale = locale
    return String(localized: label)
  }
}
