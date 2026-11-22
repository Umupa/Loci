public enum CourseToolRequest: Hashable, Codable, Sendable {
  public static let scopeMessage = "Course tools are available only in their course's active conversation."

  case ask(CourseQuestion.Draft)
  case goal(CourseGoal)
  case ready
  case addSource(CourseSource.Draft)
  case readSource(EntityID)
  case listSources
  case plan([Lesson])
  case writeLesson(Lesson.ID, markdown: String)
  case atlas(CourseAtlas)
}
