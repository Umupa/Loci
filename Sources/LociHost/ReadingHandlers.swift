import LociModel
import LociStore

extension LocalHost {
  public func lessonText(_ lesson: LessonRef) async throws(HostError) -> String {
    try attempt { try store.lesson(lesson).body }
  }

  public func lessonCitations(_ lesson: LessonRef) async throws(HostError) -> [Citation] {
    try attempt { try database.citations(in: lesson) }
  }

  public func citingLessons(of item: EntityID) async throws(HostError) -> [CitingLesson] {
    try attempt { try database.citingLessons(of: item) }
  }

  public func search(_ command: Search) async throws(HostError) -> [SearchHit] {
    try attempt { try database.search(command.text, limit: command.limit) }
  }

  public func readingState(of content: ContentRef) async throws(HostError) -> ReadingState? {
    try attempt { try database.readingState(of: content) }
  }

  public func saveReadingPosition(_ command: SaveReadingPosition) async throws(HostError) -> Done {
    try attempt {
      let finished = try database.readingState(of: command.content)?.finished ?? false
      try database.save(
        ReadingState(position: command.position, finished: finished, updatedAt: environment.now()),
        for: command.content)
    }
    return Done()
  }

  public func markRead(_ content: ContentRef) async throws(HostError) -> Done {
    try attempt {
      let position = try database.readingState(of: content)?.position
      try database.save(ReadingState(position: position, finished: true, updatedAt: environment.now()), for: content)
    }
    return Done()
  }
}
