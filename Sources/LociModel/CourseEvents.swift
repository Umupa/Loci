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
  /// Draw the atlas's skeleton, or with a lesson, add what that lesson taught to it.
  case drawAtlas(Lesson.ID?)

  public enum WriteReason: String, Hashable, Codable, Sendable {
    case firstLessons, requested
    /// Retained for reading course turns stored by earlier versions.
    case openedLastWritten
  }
}
