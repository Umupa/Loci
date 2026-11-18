import LociModel
import LociStore

extension LocalHost {
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

  /// Reading something to the end for the first time is something that happened.
  public func markRead(_ content: ContentRef) async throws(HostError) -> Done {
    let before = try attempt { try database.readingState(of: content) }
    try attempt {
      try database.save(
        ReadingState(position: before?.position, finished: true, updatedAt: environment.now()), for: content)
    }
    await hub.refresh([.reading(content)])
    if before?.finished != true, case .item(let item) = content { await happened(.finishedReading(item)) }
    return Done()
  }
}
