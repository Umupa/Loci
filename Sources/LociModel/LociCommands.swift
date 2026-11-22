/// What Loci is working on, for the line under its name.
public struct LociWorking: Subscription {
  public static let name = "loci.status"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> LociStatus {
    await handler.lociStatus()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .conversation, .turnEnded, .review, .job, .loci(.panels), .everything: true
      case .item, .notes, .reading, .media, .events, .loci, .runtime: false
      }
    }
  }
}

/// Everything the Loci page shows but a diary's text, kept current as Loci and the person change the files.
public struct LociHome: Subscription {
  public static let name = "loci.page"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> LociPage {
    try await handler.lociPage()
  }

  /// Items name the sources of memories and notes.
  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .loci(let file): file != .avatar && file != .panels
      case .turnEnded, .item, .everything: true
      case .notes, .reading, .job, .media, .conversation, .review, .events, .runtime: false
      }
    }
  }
}

/// One day's diary.
public struct OneDiary: Subscription {
  public static let name = "loci.diary"
  public let day: Day

  public init(day: Day) {
    self.day = day
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> Diary {
    try await handler.diary(of: day)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.loci(.diary)) || changes.contains(.everything)
  }
}

/// The picture the person chose for Loci; `nil` shows the app's own.
public struct LociAvatar: Subscription {
  public static let name = "loci.avatar"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> Avatar? {
    try await handler.avatar()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.loci(.avatar)) || changes.contains(.everything)
  }
}

/// Rewrites the core of `SOUL.md`; the evolved traits stay as they are. Refused when the text is blank
/// or holds a `## Evolved Traits` heading of its own. Every conversation's next turn opens a new session.
public struct SaveSoul: Command {
  public static let name = "loci.saveSoul"
  public let core: String

  public init(core: String) {
    self.core = core
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Soul {
    try await handler.saveSoul(self)
  }
}

/// Removes one entry, and the lines continuing it, from `MEMORY.md` or `USER.md`. `notFound` when no
/// entry starts with that line any more.
public struct Forget: Command {
  public static let name = "loci.forget"
  public let file: MemoryFile
  /// `MemoryEntry.line`.
  public let line: String

  public init(_ line: String, in file: MemoryFile) {
    self.file = file
    self.line = line
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.forget(self)
  }
}

/// Shows the picture as Loci everywhere, keeping it as `agent/avatar.<format>` in place of any other.
public struct SetAvatar: Command {
  public static let name = "loci.setAvatar"
  public let avatar: Avatar

  public init(_ avatar: Avatar) {
    self.avatar = avatar
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.setAvatar(self)
  }
}

/// Goes back to the app's own picture of Loci.
public struct ResetAvatar: Command {
  public static let name = "loci.resetAvatar"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.resetAvatar()
  }
}
