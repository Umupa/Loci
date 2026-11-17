/// Makes a mentor from one sentence saying what to learn. The mentor starts with an empty catalog.
public struct CreateMentor: Command {
  public static let name = "mentor.create"
  public let request: String

  public init(request: String) {
    self.request = request
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Mentor {
    try await handler.createMentor(self)
  }
}

public struct RenameMentor: Command {
  public static let name = "mentor.rename"
  public let mentor: EntityID
  public let name: String

  public init(mentor: EntityID, name: String) {
    self.mentor = mentor
    self.name = name
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Mentor {
    try await handler.renameMentor(self)
  }
}

public struct DeleteMentor: Command {
  public static let name = "mentor.delete"
  public let mentor: EntityID
  /// What happens to the notes on the mentor's lessons.
  public let notes: NotesOnDelete

  public init(mentor: EntityID, notes: NotesOnDelete) {
    self.mentor = mentor
    self.notes = notes
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.deleteMentor(self)
  }
}

public struct ListMentors: Command {
  public static let name = "mentor.list"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> [Mentor] {
    try await handler.listMentors()
  }
}

/// A mentor with its catalog.
public struct ReadCatalog: Command {
  public static let name = "mentor.catalog"
  public let mentor: EntityID

  public init(mentor: EntityID) {
    self.mentor = mentor
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> MentorPage {
    try await handler.mentorPage(mentor)
  }
}
