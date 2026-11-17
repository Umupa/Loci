import Foundation

/// What a mentor is and what it remembers: `SOUL.md` and the files under `memory/`, as the mentor wrote them.
public struct Mind: Hashable, Codable, Sendable {
  /// `nil` until the mentor's first session writes it.
  public let soul: String?
  /// Where `SOUL.md` is, on the host's Mac, for opening it in an editor there.
  public let soulFile: URL
  /// Newest first.
  public let memory: [MemoryFile]

  public init(soul: String?, soulFile: URL, memory: [MemoryFile]) {
    self.soul = soul
    self.soulFile = soulFile
    self.memory = memory
  }
}

/// One file the mentor keeps under `memory/`.
public struct MemoryFile: Hashable, Codable, Sendable {
  /// The file's path under `memory/`.
  public let name: String
  public let text: String
  public let modifiedAt: Timestamp

  public init(name: String, text: String, modifiedAt: Timestamp) {
    self.name = name
    self.text = text
    self.modifiedAt = modifiedAt
  }
}

/// A mentor's soul and memory, sent again whenever the mentor or the person changes one of the files.
public struct MentorMind: Subscription {
  public static let name = "mind"
  public let mentor: EntityID

  public init(mentor: EntityID) {
    self.mentor = mentor
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> Mind {
    try await handler.mind(of: mentor)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .mind(let id), .mentor(let id): id == mentor
      case .everything: true
      case .catalog, .lesson, .item, .notes, .conversation, .reading, .job, .itemConversation, .media: false
      }
    }
  }
}
