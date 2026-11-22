public enum CourseEvent: Hashable, Codable, Sendable {
  case started(topic: String)
  case answered(question: String, answers: [String])
  case confirmedGoal
  case askedToReviseGoal
  case beganSources
  case addedSource(CourseSource)
  case removedSource(CourseSource)
  case beganWriting
  case writeLesson(Lesson.ID, reason: WriteReason)

  public enum WriteReason: String, Hashable, Codable, Sendable {
    case firstLessons, openedLastWritten, requested
  }
}
