public struct Speaker: Hashable, Sendable, Identifiable {
  public let number: Int
  public let name: String?

  public var id: Int { number }
}

public struct RenameSpeaker: Command {
  public static let name = "item.renameSpeaker"
  public let item: EntityID
  public let speaker: Int
  public let name: String

  public init(item: EntityID, speaker: Int, name: String) {
    self.item = item
    self.speaker = speaker
    self.name = name
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.renameSpeaker(self)
  }
}
