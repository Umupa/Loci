public struct Search: RemoteCommand {
  public static let name = "search"
  public let text: String
  public let limit: Int

  public init(text: String, limit: Int = 50) {
    self.text = text
    self.limit = limit
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [SearchHit] {
    try await handler.search(self)
  }
}

public struct ReadReadingState: RemoteCommand {
  public static let name = "reading.read"
  public let content: ContentRef

  public init(content: ContentRef) {
    self.content = content
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> ReadingState? {
    try await handler.readingState(of: content)
  }
}

/// Remembers where the reader is. The position must point into the same content. Whether the content
/// was read to the end stays as it was.
public struct SaveReadingPosition: RemoteCommand {
  public static let name = "reading.position"
  public let content: ContentRef
  public let position: Locator

  public init(content: ContentRef, position: Locator) {
    self.content = content
    self.position = position
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.saveReadingPosition(self)
  }
}

/// Marks content as read to the end. It stays read when the reader goes back up.
public struct MarkRead: RemoteCommand {
  public static let name = "reading.finish"
  public let content: ContentRef

  public init(content: ContentRef) {
    self.content = content
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.markRead(content)
  }
}
