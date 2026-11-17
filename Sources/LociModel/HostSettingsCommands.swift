import Foundation

/// The language lessons are written in, as a BCP 47 tag; `nil` when mentors write in the learner's language.
public struct ReadLessonLanguage: Command {
  public static let name = "settings.lessonLanguage"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> LessonLanguage {
    try await handler.lessonLanguage()
  }
}

/// Changes the language lessons are written in from the next lesson on.
public struct SetLessonLanguage: Command {
  public static let name = "settings.setLessonLanguage"
  public let language: LessonLanguage

  public init(_ language: LessonLanguage) {
    self.language = language
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> LessonLanguage {
    try await handler.setLessonLanguage(self)
  }
}

/// The language mentors write lessons in.
public enum LessonLanguage: Hashable, Codable, Sendable {
  /// Whatever language the learner writes in.
  case learners
  /// A BCP 47 tag such as `zh-Hans` or `en`.
  case fixed(String)
}

/// Where the host keeps its files.
public struct DataLocation: Command {
  public static let name = "settings.dataLocation"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> URL {
    await handler.dataLocation()
  }
}
